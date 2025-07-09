# RamaLama Stack with PGVector

This example demonstrates how to run RamaLama Stack with PGVector as the vector database for RAG (Retrieval-Augmented Generation) instead of the default Milvus.

## Overview

This setup creates a podman pod with three containers:
- **PGVector**: PostgreSQL database with pgvector extension for vector storage
- **RamaLama Model Server**: Serves the LLM model (Llama-3.2-3B-Instruct by default)
- **Llama Stack**: The main API server that orchestrates all components

## Quick Start

### Option 1: Using podman-commands.sh

The `podman-commands.sh` script provides several commands:

```bash
# Start all services
./podman-commands.sh start

# Start the Streamlit UI (after main services are running)
./podman-commands.sh start-ui

# Stop all services
./podman-commands.sh stop

# Restart all services
./podman-commands.sh restart

# Show status
./podman-commands.sh status

# Show logs for a specific container
./podman-commands.sh logs pgvector
./podman-commands.sh logs ramalama
./podman-commands.sh logs stack

# Test the setup
./podman-commands.sh test
```

### Option 2: Using podman kube play

```bash
# Start all services including UI
podman kube play pod.yaml

# Check status
podman ps

# View logs
podman logs llama-stack-pgvector-pgvector
podman logs llama-stack-pgvector-ramalama-model
podman logs llama-stack-pgvector-llama-stack
podman logs llama-stack-pgvector-ui

# Stop all services
podman kube down pod.yaml
```

**Note:** The `podman kube play` method starts all services including the UI in a single command. Both methods expose the same ports and provide identical functionality.

## Configuration

### Default Configuration

The setup uses the following default configuration:

- **PGVector Database:**
  - Database: `rag_blueprint`
  - User: `postgres`
  - Password: `rag_password`
  - Port: `5432`

- **RamaLama Model Server:**
  - Model: `tinyllama`
  - Port: `8080`

- **Llama Stack API:**
  - Port: `8321`

- **Streamlit UI (optional):**
  - Port: `8501`

### Customization

To customize the configuration, edit the variables at the top of `podman-commands.sh`:

```bash
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="rag_password"
POSTGRES_DB="rag_blueprint"
INFERENCE_MODEL="tinyllama"
```

## Files

- `ramalama-run.yaml` - Modified Llama Stack configuration using PGVector
- `podman-commands.sh` - Main script to manage the pod and containers
- `init-db.sh` - Database initialization script
- `pod.yaml` - Kubernetes-style pod definition for `podman kube play`
- `configmap.yaml` - Kubernetes ConfigMap (reference)

## Usage

### Starting the Services

### Service Endpoints

Once running, the following endpoints are available:

- **PGVector Database:** `localhost:5432`
- **RamaLama Model Server:** `localhost:8080`
- **Llama Stack API:** `localhost:8321`
- **Streamlit UI:** `localhost:8501` (when started with `start-ui`)

### Testing the Setup

You can test the setup using the built-in test command:

```bash
./podman-commands.sh test
```

Or manually test each service:

```bash
# Test PGVector connection
podman exec llama-stack-pgvector-pgvector psql -U postgres -d rag_blueprint -c "SELECT 1;"

# Test RamaLama model server
curl http://localhost:8080/health

# Test Llama Stack API
curl http://localhost:8321/health
```

## Architecture

The setup creates a single podman pod with shared networking, allowing containers to communicate via localhost. The architecture is:

```
┌─────────────────────────────────────────────────────┐
│                 Podman Pod                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │  PGVector   │  │  RamaLama   │  │ Llama Stack │  │
│  │   :5432     │  │   :8080     │  │   :8321     │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
│                                                     │
│  Shared Network: localhost                          │
└─────────────────────────────────────────────────────┘
```

## Integration

### Using with RAG

The setup is ready for RAG applications. The Llama Stack API provides endpoints for:

- Document ingestion and embedding
- Vector similarity search
- Question answering with context

### Web UI

The Streamlit UI provides a user-friendly interface to interact with your RAG stack:

```bash
# Start the main services
./podman-commands.sh start

# Start the web UI (in a separate terminal)
./podman-commands.sh start-ui

# Access the UI at: http://localhost:8501
```

### API Examples

After starting the services, you can interact with the Llama Stack API:

```python
import requests

# Example: Health check
response = requests.get('http://localhost:8321/health')
print(response.json())

# Example: List available models
response = requests.get('http://localhost:8321/models')
print(response.json())
```

### Environment Variables

To enable additional features like web search, set environment variables before starting:

```bash
# Enable Tavily search functionality
export TAVILY_SEARCH_API_KEY="your_tavily_api_key"
./podman-commands.sh start
```
