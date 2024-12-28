import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

class RequestHandler(BaseHTTPRequestHandler):
    def __init__(self, request, client_address, server) -> None:
        super().__init__(request, client_address, server)

    def log_message(self, *args) -> None:
        pass

    def do_HEAD(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()

    def do_GET(self) -> None:
        self.do_HEAD()

        metrics = [
            *self._get_cpu_usage_metrics(),
            *self._get_memory_usage_metrics(),
            *self._get_disk_usage_metrics(),
        ]

        metrics = [f"opentelemetrystack_{metric}" for metric in metrics]
        metrics = "\n".join(metrics) + "\n"
        self.wfile.write(metrics.encode())

    def _get_cpu_usage_metrics(self) -> list[str]:
        metrics = []

        for line in Path("/sys/fs/cgroup/cpu.stat").read_text().splitlines():
            key, value = line.split()
            if key not in ["usage_usec", "user_usec", "system_usec"]:
                continue

            category = key.split("_")[0]
            value = int(value) / 1e6

            metrics.append(f"cpu_{category}_seconds_total {value}")

        return metrics

    def _get_memory_usage_metrics(self) -> list[str]:
        metrics = []

        for category, cgroup_prefix in [("physical_memory", "memory"), ("swap_memory", "memory.swap")]:
            current_bytes = Path(f"/sys/fs/cgroup/{cgroup_prefix}.current").read_text().strip()
            metrics.append(f"{category}_usage_bytes {current_bytes}")

        return metrics

    def _get_disk_usage_metrics(self) -> list[str]:
        metrics = []

        for line in subprocess.check_output(["bash", "-c", "du -sb /data/*"]).decode().splitlines():
            size_bytes, path = line.split(maxsplit=1)
            metrics.append(f'disk_usage_bytes{{path="{path}"}} {size_bytes}')

        return metrics

server = HTTPServer(("0.0.0.0", 3030), RequestHandler)
server.serve_forever()
