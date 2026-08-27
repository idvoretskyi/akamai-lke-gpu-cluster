"""Roboflow RF-DETR object-detection pipeline for Kubeflow Pipelines.

Validates the full HAMi + Kubeflow + GPU Operator stack end-to-end: a single
GPU component, orchestrated by Kubeflow Pipelines (Argo Workflows under the
hood), requests a `nvidia.com/gpu` resource. HAMi's mutating webhook should
intercept the Argo-created Pod and route it through `hami-scheduler` onto a
vGPU slice — this is a genuinely different code path from our earlier manual
Pod tests (which set `schedulerName` explicitly), because Argo/KFP has no
concept of a custom scheduler name to set.

It also proves HAMi memory *slicing* works through Kubeflow, not just GPU
*count* sharing: the KFP SDK's `set_accelerator_type()/set_accelerator_limit()`
only support one accelerator resource (`nvidia.com/gpu`), so this component
has no way to also request the `nvidia.com/gpumem` HAMi resource. Instead, it
relies on the HAMi module's `default_gpu_memory` setting (see
tofu/modules/hami/README.md) — a cluster-wide fallback slice size applied to
any `nvidia.com/gpu` request that doesn't specify `gpumem` explicitly — and
asserts that the GPU it sees is capped at that slice, not the whole physical
card.

Model: RF-DETR (https://github.com/roboflow/rf-detr), Roboflow's open-source,
Apache-2.0-licensed real-time object detector. Uses the smallest checkpoint
(RFDETRNano) and pretrained COCO weights, both of which download without any
Roboflow API key — keeping this example runnable with zero external secrets.
"""

from kfp import compiler, dsl
from kfp import kubernetes

# CUDA 12.4 in the container; the NVIDIA driver on the host only needs to be
# new enough to support it (drivers are backward-compatible with older CUDA
# runtimes) — this comfortably covers any GPU Operator-installed driver.
BASE_IMAGE = "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"

# The GPU node taint applied by this repo when dedicate_gpu_nodes = true
# (tofu/locals.tf: local.gpu_node_taint).
GPU_TAINT_KEY = "nvidia.com/gpu"
GPU_TAINT_EFFECT = "NoSchedule"

SAMPLE_IMAGE_URL = "https://media.roboflow.com/dog.jpeg"

# Must match the HAMi module's `default_gpu_memory` (tofu/variables.tf:
# hami_default_gpu_memory, default 8000 MB). 0 disables the check — set this
# to 0 if you've disabled default_gpu_memory on the HAMi side too.
EXPECTED_GPU_MEMORY_MIB = 8000


@dsl.component(base_image=BASE_IMAGE, packages_to_install=["rfdetr", "supervision"])
def detect_objects(
    image_url: str,
    confidence_threshold: float,
    expected_gpu_memory_mib: int,
) -> str:
    """Runs RF-DETR object detection on a sample image using the GPU.

    Prints CUDA/device diagnostics (confirming the pod actually got a GPU —
    HAMi vGPU slice or otherwise) plus the detected classes, and returns a
    short summary string as the component output.
    """
    import torch

    print(f"torch.cuda.is_available() = {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"torch.cuda.get_device_name(0) = {torch.cuda.get_device_name(0)}")
        props = torch.cuda.get_device_properties(0)
        total_memory_mib = props.total_memory / (1024 ** 2)
        print(f"torch.cuda memory (total) = {total_memory_mib:.0f} MiB")
    else:
        raise RuntimeError(
            "CUDA is not available inside the pod — the GPU was not "
            "injected (check the HAMi/GPU Operator RuntimeClass wiring)."
        )

    if expected_gpu_memory_mib > 0:
        # Generous tolerance: HAMi reports the slice size as configured, but
        # exact MiB/MB rounding can differ by a small amount.
        tolerance_mib = 500
        if abs(total_memory_mib - expected_gpu_memory_mib) > tolerance_mib:
            raise RuntimeError(
                f"Expected a ~{expected_gpu_memory_mib} MiB HAMi vGPU slice "
                f"(default_gpu_memory), but saw {total_memory_mib:.0f} MiB — "
                "this pod likely got the whole physical GPU instead of a "
                "memory-capped slice. Check the HAMi module's "
                "default_gpu_memory setting and that the hami-scheduler "
                "picked up the change (it only reads its config at startup)."
            )
        print(
            f"Confirmed HAMi vGPU memory slice: {total_memory_mib:.0f} MiB "
            f"(expected ~{expected_gpu_memory_mib} MiB) — this pod did NOT "
            "get the whole physical GPU."
        )

    # `supervision` (an rfdetr dependency) pulls in the GUI build of OpenCV
    # (`opencv-python`), which needs libxcb/libGL — not present in the slim
    # CUDA runtime base image. Force the headless build (no system deps)
    # before anything imports cv2; this overwrites the GUI build's files in
    # site-packages, which is the standard fix for this exact conflict.
    import subprocess
    import sys

    subprocess.run(
        [sys.executable, "-m", "pip", "install", "-q", "opencv-python-headless"],
        check=True,
    )

    from rfdetr import RFDETRNano
    from rfdetr.assets.coco_classes import COCO_CLASSES

    model = RFDETRNano()
    detections = model.predict(image_url, threshold=confidence_threshold)

    labels = [COCO_CLASSES[class_id] for class_id in detections.class_id]
    print(f"Detected {len(labels)} object(s): {labels}")
    for label, confidence in zip(labels, detections.confidence):
        print(f"  - {label}: {confidence:.2f}")

    if len(labels) == 0:
        raise RuntimeError("RF-DETR returned zero detections on the sample image.")

    return f"{len(labels)} detection(s): {', '.join(sorted(set(labels)))}"


@dsl.pipeline(
    name="roboflow-rfdetr-gpu-validation",
    description=(
        "Runs Roboflow's RF-DETR object detector on a HAMi-managed GPU "
        "slice inside a Kubeflow user namespace, validating GPU Operator + "
        "HAMi + Kubeflow Pipelines end-to-end."
    ),
)
def roboflow_pipeline(
    image_url: str = SAMPLE_IMAGE_URL,
    confidence_threshold: float = 0.5,
    expected_gpu_memory_mib: int = EXPECTED_GPU_MEMORY_MIB,
):
    task = detect_objects(
        image_url=image_url,
        confidence_threshold=confidence_threshold,
        expected_gpu_memory_mib=expected_gpu_memory_mib,
    )
    task.set_display_name("rfdetr-gpu-detect")
    task.set_caching_options(False)

    # Request one whole GPU. HAMi's admission webhook intercepts pods
    # requesting nvidia.com/gpu regardless of scheduler, mutating them onto
    # hami-scheduler + the vGPU-aware RuntimeClass — see module README at
    # tofu/modules/hami/README.md for how the slice count is configured. No
    # gpumem is set here (the KFP SDK can't express it) — the HAMi module's
    # default_gpu_memory fills that gap cluster-side.
    task.set_accelerator_type("nvidia.com/gpu")
    task.set_accelerator_limit(1)

    # Argo/KFP has no first-class "schedulerName" setting, so the taint
    # toleration must be added directly; without it the pod can never even
    # be considered for the (tainted) GPU node in the first place.
    kubernetes.add_toleration(
        task,
        key=GPU_TAINT_KEY,
        operator="Exists",
        effect=GPU_TAINT_EFFECT,
    )


if __name__ == "__main__":
    compiler.Compiler().compile(
        pipeline_func=roboflow_pipeline,
        package_path="pipeline.yaml",
    )
