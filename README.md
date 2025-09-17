# Music Cloud API

A simple backend using FastAPI and SQLAlchemy for managing users and their music library with PostgreSQL database.

## Database Schema

### Tables

1. **Usuarios** (Users)
   - `id` (PK, int, autoincrement)
   - `nombre` (string) - User's name
   - `email` (string, unique) - User's email
   - `estado` (boolean, default True) - User's status

2. **Musica** (Music)
   - `id` (PK, int, autoincrement)
   - `titulo` (string) - Song title
   - `artista` (string) - Artist name

3. **LibreriaUsuarios** (User Library)
   - `id` (PK, int, autoincrement)
   - `usuario_id` (FK -> Usuarios.id)
   - `musica_id` (FK -> Musica.id)

## Setup and Installation

### Prerequisites
- Python 3.8+
- PostgreSQL database
- Virtual environment (recommended)

### Database Configuration
The application connects to PostgreSQL with these settings:
- Host: localhost
- Port: 5432
- Database: musiccloud
- User: santiago
- Password: santiago

Make sure to create the database before running the application:
```sql
CREATE DATABASE musiccloud;
```

### Installation Steps

1. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

2. **Initialize the database with sample data**
   ```bash
   python init_data.py
   ```

3. **Run the application**
   ```bash
   python main.py
   ```

The API will be available at `http://localhost:8000`

## API Endpoints

### Base URL
```
http://localhost:8000
```

### Documentation
- Interactive API docs: `http://localhost:8000/docs`
- OpenAPI schema: `http://localhost:8000/openapi.json`

### Available Endpoints

#### 1. Create User
- **POST** `/usuarios`
- **Body**: 
  ```json
  {
    "nombre": "string",
    "email": "string"
  }
  ```
- **Response**: User object with ID
- **Status**: 201 Created

#### 2. Update User Status
- **PUT** `/usuarios/{id}/estado`
- **Body**: 
  ```json
  {
    "estado": true
  }
  ```
- **Response**: Updated user object
- **Status**: 200 OK

#### 3. Add Song to User's Library
- **POST** `/usuarios/{id}/musica`
- **Body**: 
  ```json
  {
    "musica_id": 1
  }
  ```
- **Response**: Success message
- **Status**: 200 OK

#### 4. Get All Songs
- **GET** `/musica`
- **Response**: Array of song objects
- **Status**: 200 OK

#### 5. Get User Profile
- **GET** `/usuarios/{id}`
- **Response**: User object with their music library
- **Status**: 200 OK

#### 6. Create Song (For Testing)
- **POST** `/musica`
- **Body**: 
  ```json
  {
    "titulo": "string",
    "artista": "string"
  }
  ```
- **Response**: Created song object
- **Status**: 201 Created

## Example Usage

### Create a new user
```bash
curl -X POST "http://localhost:8000/usuarios" \
     -H "Content-Type: application/json" \
     -d '{"nombre": "John Doe", "email": "john@example.com"}'
```

### Get all songs
```bash
curl "http://localhost:8000/musica"
```

### Add song to user's library
```bash
curl -X POST "http://localhost:8000/usuarios/1/musica" \
     -H "Content-Type: application/json" \
     -d '{"musica_id": 1}'
```

### Get user profile with music library
```bash
curl "http://localhost:8000/usuarios/1"
```

### Update user status
```bash
curl -X PUT "http://localhost:8000/usuarios/1/estado" \
     -H "Content-Type: application/json" \
     -d '{"estado": false}'
```

## Error Handling

The API returns appropriate HTTP status codes and error messages:

- **400 Bad Request**: Invalid input data (e.g., email already exists)
- **404 Not Found**: Resource not found (user or song)
- **422 Unprocessable Entity**: Validation errors

Example error response:
```json
{
  "detail": "User not found"
}
```

## Testing

Run the test script to verify all endpoints:
```bash
pip install requests  # If not already installed
python test_api.py
```

Make sure the server is running before executing the tests.

## Technologies Used

- **FastAPI**: Modern, fast web framework for building APIs
- **SQLAlchemy**: Python SQL toolkit and ORM
- **PostgreSQL**: Robust, open-source relational database
- **Pydantic**: Data validation using Python type annotations
- **Uvicorn**: ASGI server for running the application
