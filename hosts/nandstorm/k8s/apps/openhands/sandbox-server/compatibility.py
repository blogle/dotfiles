from fastapi import FastAPI, Response

from openhands.app_server.app import app as upstream_app


app = FastAPI()


@app.get("/api/keys/current")
async def current_api_key():
    # Agent Canvas treats HTTP 400 as a valid legacy cloud API key.
    return Response(status_code=400)


@app.get("/api/organizations")
async def organizations():
    # OSS single-tenant mode has no organizations.
    return {
        "items": [],
        "current_org_id": None,
    }


app.mount("/", upstream_app)
