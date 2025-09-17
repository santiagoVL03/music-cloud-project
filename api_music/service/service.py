# Service layer for music cloud project

from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from api_music.repository.repository import UsuarioRepository, MusicaRepository, LibreriaRepository
from api_music.schema.schema import (
    UsuarioCreate, UsuarioResponse, UsuarioProfileResponse, 
    MusicaResponse, AddMusicaToUser, MusicaCreate
)
from typing import List


class UsuarioService:
    def __init__(self, db: Session):
        self.usuario_repo = UsuarioRepository(db)
        self.libreria_repo = LibreriaRepository(db)

    def create_usuario(self, usuario: UsuarioCreate) -> UsuarioResponse:
        # Check if email already exists
        existing_user = self.usuario_repo.get_usuario_by_email(usuario.email)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )
        
        db_usuario = self.usuario_repo.create_usuario(usuario)
        return UsuarioResponse.model_validate(db_usuario)

    def update_usuario_estado(self, usuario_id: int, estado: bool) -> UsuarioResponse:
        db_usuario = self.usuario_repo.update_usuario_estado(usuario_id, estado)
        if not db_usuario:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        return UsuarioResponse.model_validate(db_usuario)

    def get_usuario_profile(self, usuario_id: int) -> UsuarioProfileResponse:
        db_usuario = self.usuario_repo.get_usuario_by_id(usuario_id)
        if not db_usuario:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        # Get user's music
        musica_list = self.libreria_repo.get_usuario_musica(usuario_id)
        
        return UsuarioProfileResponse(
            id=db_usuario.id,
            nombre=db_usuario.nombre,
            email=db_usuario.email,
            estado=db_usuario.estado,
            musica=[MusicaResponse.model_validate(m) for m in musica_list]
        )

    def add_musica_to_usuario(self, usuario_id: int, add_musica: AddMusicaToUser) -> dict:
        # Check if user exists
        db_usuario = self.usuario_repo.get_usuario_by_id(usuario_id)
        if not db_usuario:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        # Check if music exists
        musica_repo = MusicaRepository(self.usuario_repo.db)
        db_musica = musica_repo.get_musica_by_id(add_musica.musica_id)
        if not db_musica:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Music not found"
            )
        
        # Add music to user's library
        self.libreria_repo.add_musica_to_usuario(usuario_id, add_musica.musica_id)
        
        return {"message": "Music added to user's library successfully"}


class MusicaService:
    def __init__(self, db: Session):
        self.musica_repo = MusicaRepository(db)

    def get_all_musica(self) -> List[MusicaResponse]:
        musica_list = self.musica_repo.get_all_musica()
        return [MusicaResponse.model_validate(m) for m in musica_list]

    def create_musica(self, musica: MusicaCreate) -> MusicaResponse:
        db_musica = self.musica_repo.create_musica(musica)
        return MusicaResponse.model_validate(db_musica)
