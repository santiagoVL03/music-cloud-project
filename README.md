# Music Cloud API

A simple backend using FastAPI and SQLAlchemy for managing users and their music library with PostgreSQL database. The infrastructure is managed using OpenTofu for automatic scaling on AWS.

## Infrastructure with OpenTofu

This project uses **OpenTofu** (an open-source Terraform alternative) to provision and manage cloud infrastructure on AWS with automatic scaling capabilities.

### OpenTofu Files Overview

#### `opentofu_scaler/main.tf`
The main infrastructure configuration file that defines:

- **VPC and Networking**: Creates a Virtual Private Cloud (10.0.0.0/16) with two public subnets across different availability zones (us-east-1a and us-east-1b) for high availability
- **Internet Gateway and Route Tables**: Enables internet access for the public subnets
- **Security Groups**:
  - `web_sg`: Allows HTTP (port 80), SSH (port 22), and internal VPC communication for web instances
  - `db_sg`: Allows PostgreSQL (port 5432) from web instances, SSH access, and internal VPC traffic
- **Database Instance**: Deploys a t3.micro EC2 instance running PostgreSQL 13 in a Docker container with the musiccloud database. Includes **Amazon CloudWatch Agent** for monitoring CPU and memory metrics
- **Launch Template**: Defines the configuration for web server instances that run the musiccloud-web Docker container, automatically connecting to the database. Also includes **CloudWatch Agent** for detailed monitoring
- **Application Load Balancer**: Distributes incoming HTTP traffic across multiple web instances
- **Auto Scaling Group**: Automatically scales web instances between 1 and 3 based on demand, with health checks via the load balancer
- **Auto Scaling Policies**:
  - `scale_up`: Adds one instance when CPU > 70% for 2 consecutive periods (300s cooldown)
  - `scale_down`: Removes one instance when CPU < 30% for 2 consecutive periods (300s cooldown)
- **CloudWatch Alarms**:
  - `high_cpu_alarm`: Triggers scale-up when average CPU utilization exceeds 70% over 4 minutes
  - `low_cpu_alarm`: Triggers scale-down when average CPU utilization falls below 30% over 4 minutes
- **Monitoring Integration**: CloudWatch Agent collects custom metrics including:
  - Memory usage percentage (`mem_used_percent`)
  - CPU usage statistics (`cpu_usage_idle`, `cpu_usage_user`, `cpu_usage_system`)
  - Metrics collected every 60 seconds for detailed monitoring

#### `opentofu_scaler/variables.tf`
Defines configurable variables for the infrastructure:

- `aws_region`: The AWS region where resources will be deployed (default: us-east-1)

This allows easy customization without modifying the main configuration.

#### `opentofu_scaler/outputs.tf`
Exports important information after deployment:

- `load_balancer_dns`: The DNS name of the Application Load Balancer, which is the public endpoint to access your API

### Deploying with OpenTofu

1. **Install OpenTofu** (if not already installed):
   ```bash
   # On Linux
   curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | bash
   ```

2. **Configure AWS credentials**:
   ```bash
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   ```

3. **Initialize OpenTofu**:
   ```bash
   cd opentofu_scaler
   tofu init
   ```

4. **Plan the deployment** (review what will be created):
   ```bash
   tofu plan
   ```

5. **Apply the configuration**:
   ```bash
   tofu apply
   ```
   Type `yes` when prompted to confirm.

6. **Access your API**:
   After deployment, OpenTofu will output the Load Balancer DNS. Use this URL to access your API:
   ```
   http://<load_balancer_dns>/docs
   ```

7. **Destroy the infrastructure** (when done):
   ```bash
   tofu destroy
   ```

### Auto-Scaling Features

The infrastructure automatically scales based on CPU utilization metrics:

#### Scaling Behavior
- **Minimum instances**: 1 (always at least one web server running)
- **Maximum instances**: 3 (scales up to three web servers under high load)
- **Desired capacity**: 1 (starting point)
- **Health checks**: Unhealthy instances are automatically replaced via ELB health checks
- **Load balancing**: Traffic is evenly distributed across all healthy instances

#### Scaling Policies
- **Scale Up**: 
  - **Trigger**: Average CPU utilization > 70% for 4 minutes (2 evaluation periods of 120 seconds)
  - **Action**: Add 1 instance
  - **Cooldown**: 300 seconds (5 minutes) before another scale-up can occur
  
- **Scale Down**: 
  - **Trigger**: Average CPU utilization < 30% for 4 minutes (2 evaluation periods of 120 seconds)
  - **Action**: Remove 1 instance
  - **Cooldown**: 300 seconds (5 minutes) before another scale-down can occur

#### Monitoring with CloudWatch
All EC2 instances (both database and web servers) are equipped with the **Amazon CloudWatch Agent** that provides:

- **Real-time Metrics**:
  - CPU usage breakdown (idle, user, system)
  - Memory utilization percentage
  - Collected every 60 seconds for granular insights

- **Benefits**:
  - Better visibility into resource utilization
  - More accurate scaling decisions based on actual system load
  - Ability to set up custom alarms for memory-based scaling (if needed)
  - Historical data for capacity planning

You can view these metrics in the AWS CloudWatch console under the EC2 namespace and custom metrics.

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
