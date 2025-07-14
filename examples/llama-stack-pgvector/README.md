# RamaLama Stack with PGVector and Pre-loaded Database

This example demonstrates how to run RamaLama Stack with PGVector as the vector database for RAG, using a custom PostgreSQL image with pre-loaded data.

## Overview

This setup creates a podman pod with four containers:
- **PGVector**: PostgreSQL database with pgvector extension and pre-loaded data from a database dump
- **RamaLama Model Server**: Serves the LLM model
- **Llama Stack**: The main API server that orchestrates all components
- **Streamlit UI**: Optional web interface for interacting with the RAG stack

## Prerequisites

### Building the Custom PGVector Image

Before running the pod, you need to build a custom PostgreSQL image with your data pre-loaded:

1. **Prepare your database dump**: Place your `ragdb.dump` file in the same directory as the `Containerfile`

2. **Build the PGVector image**:
```bash
# Ensure ragdb.dump is in the current directory
ls ragdb.dump

# Build the custom PostgreSQL image
podman build -t rag-pgvector -f Containerfile .

# Tag and push to your registry (optional)
podman tag rag-pgvector quay.io/your-username/pgrag:latest
podman push quay.io/your-username/pgrag:latest
```

**Note**: Update the image name in `pod.yaml` to match your built image.

## Quick Start

### Running the Complete Stack

```bash
# Start all services using ConfigMap configuration
podman kube play --configmap ./configmap.yaml ./pod.yaml

# Check status
podman ps

# View logs
podman logs ls-rag-pgvector-pgvector
podman logs ls-rag-pgvector-ramalama-model
podman logs ls-rag-pgvector-llama-stack
podman logs ls-rag-pgvector-ui

# Stop all services
podman kube down pod.yaml
```

## Configuration

### Database Configuration

The setup uses the following database configuration:

- **Database Name:** `ragdb`
- **User:** `postgres`
- **Password:** `postgres`
- **Port:** `5432`

### Model Configuration

- **LLM Model:** `granite3.3`
- **Embedding Model:** `all-MiniLM-L6-v2` (384 dimensions)
- **RamaLama Model Server Port:** `8080`

### Vector Database Configuration

The vector database is automatically configured with:
- **Vector DB ID:** `ragdb`
- **Provider:** `pgvector`
- **Embedding Model:** `all-MiniLM-L6-v2`
- **Embedding Dimension:** `384`

## Files

- `Containerfile` - Custom PostgreSQL image with pre-loaded data
- `db-load/loader.sh` - Database loading script (runs automatically on container startup)
- `db-load/loader.service` - Systemd service for database loading
- `configmap.yaml` - Kubernetes ConfigMap containing llama-stack configuration
- `pod.yaml` - Pod definition

## Usage

### Service Endpoints

Once running, the following endpoints are available:

- **PGVector Database:** `localhost:5432`
- **RamaLama Model Server:** `localhost:8080`
- **Llama Stack API:** `localhost:8321`
- **Streamlit UI:** `localhost:8501`

### Testing the Setup

Test each service manually:

```bash
# Test PGVector connection
podman exec ls-rag-pgvector-pgvector psql -U postgres -d ragdb -c "SELECT 1;"

# Test RamaLama model server
curl http://localhost:8080/health

# Test Llama Stack
curl http://localhost:8321/v1/models

# Test vector database
curl http://localhost:8321/v1/vector_dbs
```

## Architecture

The setup creates a single podman pod with shared networking:

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Podman Pod                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │  PGVector   │  │  RamaLama   │  │ Llama Stack │  │ Streamlit   │ │
│  │   :5432     │  │   :8080     │  │   :8321     │  │ UI :8501    │ │
│  │ (systemd)   │  │             │  │             │  │             │ │
│  │ ragdb.dump  │  │             │  │             │  │  (optional) │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                                     │
│  Shared Network: localhost                                          │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Features

- **Pre-loaded Data**: Database is initialized with your data on first startup
- **Systemd Management**: PostgreSQL runs under systemd for proper service management
- **Shared Memory**: Configured with tmpfs for PostgreSQL shared memory requirements
- **Vector Search**: Ready for RAG operations with pre-configured vector database

### Web UI

The Streamlit UI provides a user-friendly interface to interact with your RAG stack:

```
Access the UI at: http://localhost:8501
```

## Environment Variables

The following environment variables can be set to enable additional features:

```bash
# Enable Tavily search functionality (optional)
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
