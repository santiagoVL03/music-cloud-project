# Pydantic schemas for music cloud project

from pydantic import BaseModel
from typing import List


# Usuario schemas
class UsuarioCreate(BaseModel):
    nombre: str
    email: str


class UsuarioUpdate(BaseModel):
    estado: bool


class MusicaResponse(BaseModel):
    id: int
    titulo: str
    artista: str

    class Config:
        from_attributes = True


class UsuarioResponse(BaseModel):
    id: int
    nombre: str
    email: str
    estado: bool

    class Config:
        from_attributes = True


class UsuarioProfileResponse(BaseModel):
    id: int
    nombre: str
    email: str
    estado: bool
    musica: List[MusicaResponse] = []

    class Config:
        from_attributes = True


# Musica schemas
class MusicaCreate(BaseModel):
    titulo: str
    artista: str


# LibreriaUsuarios schemas
class AddMusicaToUser(BaseModel):
    musica_id: int


# Error response schema
class ErrorResponse(BaseModel):
    detail: str
