# RamaLama Stack with PGVector

This example demonstrates how to run RamaLama Stack with PGVector as the vector database for RAG.

## Overview

This setup creates a podman pod with four containers:
- **PGVector**: PostgreSQL database with pgvector extension for vector storage
- **RamaLama Model Server**: Serves the LLM model
- **Llama Stack**: The main API server that orchestrates all components
- **Streamlit UI**: Optional web interface for interacting with the RAG stack

## Quick Start

### Option 1: Using podman kube play

#### Option 1a: With ConfigMap
```bash
# Start all services including UI with ConfigMap for llama-stack run configuration
podman kube play --configmap configmap.yaml pod-with-configmap.yaml

# Check status
podman ps

# View logs
podman logs llama-stack-pgvector-pgvector
podman logs llama-stack-pgvector-ramalama-model
podman logs llama-stack-pgvector-llama-stack
podman logs llama-stack-pgvector-ui

# Stop all services
podman kube down pod-with-configmap.yaml
```

#### Option 1b: With hostPath volumes (requires SELinux context confg)
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

**Note:** The `podman kube play` method starts all services including the UI in a single command. All deployment methods expose the same ports and provide
identical functionality. With Option 2 below, you have the option of deploying without the added UI, and can add it after starting the main pod.

### Option 2: Using podman-commands.sh

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
- `pod.yaml` - Kubernetes-style pod definition with hostPath volumes
- `pod-with-configmap.yaml` - Kubernetes-style pod definition using ConfigMap for llama-stack run config
- `configmap.yaml` - Kubernetes ConfigMap containing llama-stack run config

## Usage

### Service Endpoints

Once running, the following endpoints are available:

- **PGVector Database:** `localhost:5432`
- **RamaLama Model Server:** `localhost:8080`
- **Llama Stack API:** `localhost:8321`
- **Streamlit UI:** `localhost:8501`

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

# Test Llama Stack
curl http://localhost:8321/v1/models
```

## Architecture

The setup creates a single podman pod with shared networking, allowing containers to communicate via localhost. The architecture is:

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Podman Pod                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │  PGVector   │  │  RamaLama   │  │ Llama Stack │  │ Streamlit   │ │
│  │   :5432     │  │   :8080     │  │   :8321     │  │ UI :8501    │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                     │               │
│  Shared Network: localhost                          │   (optional)  │
└─────────────────────────────────────────────────────────────────────┘
```

### Web UI

The Streamlit UI provides a user-friendly interface to interact with your RAG stack.

```
Access the UI at: http://localhost:8501
```

### API Examples

After starting the services, you can interact with the Llama Stack API:

```python
import requests

# Example: Health check
response = requests.get('http://localhost:8080/health')
print(response.json())

# Example: List available models
response = requests.get('http://localhost:8321/v1/models')
print(response.json())
```

### Environment Variables

To enable additional features like web search, set environment variables before starting:

```bash
# Enable Tavily search functionality
export TAVILY_SEARCH_API_KEY="your_tavily_api_key"
```

## Building Images from Source

If you need to build the container images yourself from the ramalama repository:

### Building ramalama-stack Image
```bash
# From the ramalama repository root
podman build -t quay.io/sallyom/ramalama-stack:ubi10 -f container-images/llama-stack/Containerfile .
```

### Building ramalama Image
```bash
# From the ramalama repository root
REGISTRY_PATH=quay.io/sallyom make build IMAGE=ramalama
```
### Building the UI Image
```bash
# Clone the llama-stack repository
git clone https://github.com/meta-llama/llama-stack
cd llama-stack/llama_stack/distributions/ui

# Build the UI image
podman build -t ramalama-stack:ui .
```
