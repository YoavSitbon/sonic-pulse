"""Application entrypoint for the API and audio-analysis roles."""

import os

from dotenv import load_dotenv

load_dotenv()

from app_factory import create_app
from utils.logging import log_info

app = create_app()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5001))
    log_info(f"Starting {os.environ.get('SERVICE_ROLE', 'monolith')} service on port {port}")
    app.run(host="0.0.0.0", port=port, debug=False)
