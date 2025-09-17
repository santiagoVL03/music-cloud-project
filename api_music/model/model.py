# SQLAlchemy models for music cloud project

from sqlalchemy import Column, Integer, String, Boolean, ForeignKey
from sqlalchemy.orm import relationship
from api_music.config.config import Base


class Usuarios(Base):
    __tablename__ = "usuarios"
    
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    nombre = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False, index=True)
    estado = Column(Boolean, default=True, nullable=False)
    
    # Relationship to LibreriaUsuarios
    libreria = relationship("LibreriaUsuarios", back_populates="usuario")


class Musica(Base):
    __tablename__ = "musica"
    
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    titulo = Column(String, nullable=False)
    artista = Column(String, nullable=False)
    
    # Relationship to LibreriaUsuarios
    libreria = relationship("LibreriaUsuarios", back_populates="musica")


class LibreriaUsuarios(Base):
    __tablename__ = "libreria_usuarios"
    
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    musica_id = Column(Integer, ForeignKey("musica.id"), nullable=False)
    
    # Relationships
    usuario = relationship("Usuarios", back_populates="libreria")
    musica = relationship("Musica", back_populates="libreria")
