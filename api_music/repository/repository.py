# Repository layer for music cloud project

from sqlalchemy.orm import Session
from sqlalchemy import and_
from api_music.model.model import Usuarios, Musica, LibreriaUsuarios
from api_music.schema.schema import UsuarioCreate, MusicaCreate
from typing import List, Optional


class UsuarioRepository:
    def __init__(self, db: Session):
        self.db = db

    def create_usuario(self, usuario: UsuarioCreate) -> Usuarios:
        db_usuario = Usuarios(
            nombre=usuario.nombre,
            email=usuario.email
        )
        self.db.add(db_usuario)
        self.db.commit()
        self.db.refresh(db_usuario)
        return db_usuario

    def get_usuario_by_id(self, usuario_id: int) -> Optional[Usuarios]:
        return self.db.query(Usuarios).filter(Usuarios.id == usuario_id).first()

    def get_usuario_by_email(self, email: str) -> Optional[Usuarios]:
        return self.db.query(Usuarios).filter(Usuarios.email == email).first()

    def update_usuario_estado(self, usuario_id: int, estado: bool) -> Optional[Usuarios]:
        db_usuario = self.get_usuario_by_id(usuario_id)
        if db_usuario:
            db_usuario.estado = estado
            self.db.commit()
            self.db.refresh(db_usuario)
        return db_usuario


class MusicaRepository:
    def __init__(self, db: Session):
        self.db = db

    def create_musica(self, musica: MusicaCreate) -> Musica:
        db_musica = Musica(
            titulo=musica.titulo,
            artista=musica.artista
        )
        self.db.add(db_musica)
        self.db.commit()
        self.db.refresh(db_musica)
        return db_musica

    def get_all_musica(self) -> List[Musica]:
        return self.db.query(Musica).all()

    def get_musica_by_id(self, musica_id: int) -> Optional[Musica]:
        return self.db.query(Musica).filter(Musica.id == musica_id).first()


class LibreriaRepository:
    def __init__(self, db: Session):
        self.db = db

    def add_musica_to_usuario(self, usuario_id: int, musica_id: int) -> LibreriaUsuarios:
        # Check if the relationship already exists
        existing = self.db.query(LibreriaUsuarios).filter(
            and_(
                LibreriaUsuarios.usuario_id == usuario_id,
                LibreriaUsuarios.musica_id == musica_id
            )
        ).first()
        
        if existing:
            return existing
        
        db_libreria = LibreriaUsuarios(
            usuario_id=usuario_id,
            musica_id=musica_id
        )
        self.db.add(db_libreria)
        self.db.commit()
        self.db.refresh(db_libreria)
        return db_libreria

    def get_usuario_musica(self, usuario_id: int) -> List[Musica]:
        return self.db.query(Musica).join(
            LibreriaUsuarios, Musica.id == LibreriaUsuarios.musica_id
        ).filter(LibreriaUsuarios.usuario_id == usuario_id).all()
