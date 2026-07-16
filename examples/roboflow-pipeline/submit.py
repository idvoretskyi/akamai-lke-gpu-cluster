"""Submit and monitor the Roboflow RF-DETR pipeline against a Kubeflow
Pipelines API server reached via `kubectl port-forward`, bypassing the Istio
ingress/oauth2-proxy/Dex chain by setting the same identity header the mesh
would otherwise inject (`kubeflow-userid`, see the pipeline-install-config
ConfigMap in the kubeflow namespace).

Usage:
    kubectl port-forward -n kubeflow svc/ml-pipeline 8888:8888 &
    python submit.py [--user user@example.com] [--namespace kubeflow-user-example-com]
"""

import argparse
import sys
import time

import kfp

from pipeline import roboflow_pipeline

DEFAULT_HOST = "http://localhost:8888"
DEFAULT_USER = "user@example.com"
DEFAULT_NAMESPACE = "kubeflow-user-example-com"
POLL_INTERVAL_SECONDS = 15


def build_client(host: str, user: str, namespace: str) -> kfp.Client:
    client = kfp.Client(host=host, namespace=namespace)
    # Multi-user KFP identifies the caller via this header (normally injected
    # by the Istio/oauth2-proxy/Dex chain); set it manually since we're
    # talking to the ml-pipeline Service directly through a port-forward.
    # (kfp.Client doesn't expose the underlying ApiClient directly, but every
    # generated sub-API — e.g. _run_api — holds the same shared instance.)
    client._run_api.api_client.set_default_header("kubeflow-userid", user)
    return client


def run(host: str, user: str, namespace: str, wait: bool, timeout: int) -> int:
    client = build_client(host, user, namespace)

    print(f"Submitting run against {host} (namespace={namespace}, user={user})...")
    run_result = client.create_run_from_pipeline_func(
        roboflow_pipeline,
        arguments={},
        experiment_name="roboflow-rfdetr-validation",
        namespace=namespace,
        enable_caching=False,
    )
    run_id = run_result.run_id
    print(f"Run submitted: {run_id}")
    print(f"UI: {host.replace('8888', '8080')}/pipeline/#/runs/details/{run_id}")

    if not wait:
        return 0

    deadline = time.time() + timeout
    last_state = None
    while time.time() < deadline:
        detail = client.get_run(run_id=run_id)
        state = detail.state
        if state != last_state:
            print(f"Run state: {state}")
            last_state = state
        if state in ("SUCCEEDED", "FAILED", "ERROR", "SKIPPED"):
            break
        time.sleep(POLL_INTERVAL_SECONDS)
    else:
        print(f"Timed out after {timeout}s waiting for run {run_id}")
        return 1

    if last_state != "SUCCEEDED":
        print(f"Run did not succeed (final state: {last_state})")
        return 1

    print("Run succeeded.")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--user", default=DEFAULT_USER)
    parser.add_argument("--namespace", default=DEFAULT_NAMESPACE)
    parser.add_argument("--no-wait", dest="wait", action="store_false")
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()

    sys.exit(run(args.host, args.user, args.namespace, args.wait, args.timeout))
