from api_music.config.config import SessionLocal, engine, Base
from api_music.model.model import Musica, Usuarios, LibreriaUsuarios

def init_db():
    """Crear las tablas y datos iniciales"""
    Base.metadata.create_all(bind=engine)
    
    # Crear sesión
    db = SessionLocal()
    
    try:
        existing_music = db.query(Musica).first()
        if existing_music:
            print("La base de datos ya tiene datos.")
            return
        
        users_data = [
            {"nombre": "Juan Pérez", "email": "juan@example.com", "estado": True},
            {"nombre": "María García", "email": "maria@example.com", "estado": True},
            {"nombre": "Carlos López", "email": "carlos@example.com", "estado": False},
        ]
        
        # Crear usuarios
        for user_item in users_data:
            usuario = Usuarios(
                nombre=user_item["nombre"],
                email=user_item["email"],
                estado=user_item["estado"]
            )
            db.add(usuario)
        
        db.commit()
        
        music_data = [
            {"titulo": "Bohemian Rhapsody", "artista": "Queen"},
            {"titulo": "Imagine", "artista": "John Lennon"},
            {"titulo": "Hotel California", "artista": "Eagles"},
            {"titulo": "Stairway to Heaven", "artista": "Led Zeppelin"},
            {"titulo": "Billie Jean", "artista": "Michael Jackson"},
            {"titulo": "Like a Rolling Stone", "artista": "Bob Dylan"},
            {"titulo": "Smells Like Teen Spirit", "artista": "Nirvana"},
            {"titulo": "Yesterday", "artista": "The Beatles"},
            {"titulo": "Purple Haze", "artista": "Jimi Hendrix"},
            {"titulo": "What's Going On", "artista": "Marvin Gaye"}
        ]
        
        for music_item in music_data:
            musica = Musica(
                titulo=music_item["titulo"],
                artista=music_item["artista"]
            )
            db.add(musica)
        
        db.commit()
        
        users = db.query(Usuarios).all()
        songs = db.query(Musica).all()
        
        library_data = [
            {"usuario_id": users[0].id, "musica_id": songs[0].id},
            {"usuario_id": users[0].id, "musica_id": songs[1].id},
            {"usuario_id": users[1].id, "musica_id": songs[2].id},
            {"usuario_id": users[1].id, "musica_id": songs[3].id},
            {"usuario_id": users[1].id, "musica_id": songs[4].id},
        ]
        
        for lib_item in library_data:
            libreria = LibreriaUsuarios(
                usuario_id=lib_item["usuario_id"],
                musica_id=lib_item["musica_id"]
            )
            db.add(libreria)
        
        db.commit()
        print(f"Se agregaron {len(users_data)} usuarios a la base de datos.")
        print(f"Se agregaron {len(music_data)} canciones a la base de datos.")
        print(f"Se agregaron {len(library_data)} entradas de librería a la base de datos.")
        
    except Exception as e:
        print(f"Error al inicializar datos: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    init_db()
