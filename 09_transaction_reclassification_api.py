#! /usr/bin/env python3
import os
import uvicorn
from teller.teller_reclassification_api import create_app


def main():
    host = os.environ.get("TELLER_CLASSIFIER_API_HOST", "127.0.0.1")
    port = int(os.environ.get("TELLER_CLASSIFIER_API_PORT", "8787"))
    uvicorn.run(create_app(), host=host, port=port)


if __name__ == "__main__":
    main()
