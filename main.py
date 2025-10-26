from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api_music.router.router import router as api_music_router
from api_music.config.config import engine, Base

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Music Cloud API",
    description="A simple backend for managing users and their music library",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_music_router)

@app.get("/")
async def root():
    return {"message": "Welcome to the Music Cloud API"}

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
