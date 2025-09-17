# Router for music cloud project

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from api_music.config.config import get_db
from api_music.service.service import UsuarioService, MusicaService
from api_music.schema.schema import (
    UsuarioCreate, UsuarioResponse, UsuarioProfileResponse, UsuarioUpdate,
    MusicaResponse, AddMusicaToUser, MusicaCreate
)
from typing import List

router = APIRouter()


# Usuario endpoints
@router.post("/usuarios", response_model=UsuarioResponse, status_code=status.HTTP_201_CREATED)
async def create_usuario(usuario: UsuarioCreate, db: Session = Depends(get_db)):
    """Create a new user"""
    print("Creating user...")
    service = UsuarioService(db)
    return service.create_usuario(usuario)


@router.put("/usuarios/{usuario_id}/estado", response_model=UsuarioResponse)
async def update_usuario_estado(
    usuario_id: int, 
    usuario_update: UsuarioUpdate, 
    db: Session = Depends(get_db)
):
    """Update user status"""
    service = UsuarioService(db)
    return service.update_usuario_estado(usuario_id, usuario_update.estado)


@router.post("/usuarios/{usuario_id}/musica")
async def add_musica_to_usuario(
    usuario_id: int, 
    add_musica: AddMusicaToUser, 
    db: Session = Depends(get_db)
):
    """Add a song to user's library"""
    service = UsuarioService(db)
    return service.add_musica_to_usuario(usuario_id, add_musica)


@router.get("/usuarios/{usuario_id}", response_model=UsuarioProfileResponse)
async def get_usuario_profile(usuario_id: int, db: Session = Depends(get_db)):
    """Get user profile with their music library"""
    service = UsuarioService(db)
    return service.get_usuario_profile(usuario_id)


# Musica endpoints
@router.get("/musica", response_model=List[MusicaResponse])
async def get_all_musica(db: Session = Depends(get_db)):
    """Get all songs"""
    service = MusicaService(db)
    return service.get_all_musica()


@router.post("/musica", response_model=MusicaResponse, status_code=status.HTTP_201_CREATED)
async def create_musica(musica: MusicaCreate, db: Session = Depends(get_db)):
    """Create a new song (for testing purposes)"""
    service = MusicaService(db)
    return service.create_musica(musica)
