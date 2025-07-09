#!/bin/bash

# Podman Pod Setup for RamaLama Stack with PGVector
# This script sets up and runs ramalama-stack with PGVector as the RAG database
# Compatible with Linux and macOS

set -e

# Detect OS for cross-platform compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MACOS=true
    TEMP_DIR="$(mktemp -d)"
else
    IS_MACOS=false
    TEMP_DIR="/tmp"
fi

# Configuration
POD_NAME="llama-stack-pgvector"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="rag_password"
POSTGRES_DB="rag_blueprint"
POSTGRES_PORT="5432"
LLAMA_STACK_PORT="8321"
RAMALAMA_PORT="8080"
INFERENCE_MODEL="tinyllama"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if pod exists
check_pod_exists() {
    podman pod exists "$POD_NAME" 2>/dev/null
}

# Function to create the pod
create_pod() {
    print_status "Creating podman pod: $POD_NAME"
    podman pod create \
        --name "$POD_NAME" \
        --publish "$POSTGRES_PORT:$POSTGRES_PORT" \
        --publish "$LLAMA_STACK_PORT:$LLAMA_STACK_PORT" \
        --publish "$RAMALAMA_PORT:$RAMALAMA_PORT" \
        --publish "8501:8501"
}

# Function to run PGVector container
run_pgvector() {
    print_status "Starting PGVector container"
    
    # Create volume for postgres data
    podman volume create pgvector-data || true
    
    # Create init script
    cat > "$TEMP_DIR/init-pgvector.sh" << 'EOF'
#!/bin/bash
set -e

# Create the database and enable vector extension
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
    
    -- Grant necessary permissions
    GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;
    
    -- Create a table for testing vector operations (optional)
    CREATE TABLE IF NOT EXISTS embeddings (
        id SERIAL PRIMARY KEY,
        content TEXT,
        embedding VECTOR(384)
    );
EOSQL

echo "PGVector database initialized successfully"
EOF

    chmod +x "$TEMP_DIR/init-pgvector.sh"
    
    podman run -d \
        --name "${POD_NAME}-pgvector" \
        --pod "$POD_NAME" \
        --env POSTGRES_USER="$POSTGRES_USER" \
        --env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --env POSTGRES_DB="$POSTGRES_DB" \
        --volume "$TEMP_DIR/init-pgvector.sh:/docker-entrypoint-initdb.d/init-pgvector.sh:ro" \
        --volume pgvector-data:/var/lib/postgresql/data \
        --health-cmd="pg_isready -U $POSTGRES_USER -d $POSTGRES_DB" \
        --health-interval=10s \
        --health-timeout=5s \
        --health-retries=5 \
        docker.io/pgvector/pgvector:pg17
}

# Function to run RamaLama model server
run_ramalama_model() {
    print_status "Starting RamaLama model server"
    
    podman run -d \
        --name "${POD_NAME}-ramalama" \
        --pod "$POD_NAME" \
        --env RAMALAMA_PORT="$RAMALAMA_PORT" \
        quay.io/sallyom/ramalama:latest \
        ramalama serve --port="$RAMALAMA_PORT" --host=0.0.0.0 "$INFERENCE_MODEL"
}

# Function to run Llama Stack
run_llama_stack() {
    print_status "Starting Llama Stack"
    
    # Create ramalama-run.yaml config
    cat > "$TEMP_DIR/ramalama-run.yaml" << 'EOF'
version: '2'
image_name: ramalama
apis:
- agents
- datasetio
- eval
- inference
- post_training
- safety
- scoring
- telemetry
- tool_runtime
- vector_io
providers:
  agents:
  - provider_id: meta-reference
    provider_type: inline::meta-reference
    config:
      persistence_store:
        type: sqlite
        namespace: null
        db_path: ${env.SQLITE_STORE_DIR:=~/.llama/distributions/ramalama}/agents_store.db
      responses_store:
        type: sqlite
        db_path: ${env.SQLITE_STORE_DIR:=~/.llama/distributions/ramalama}/responses_store.db
  datasetio:
  - provider_id: huggingface
    provider_type: remote::huggingface
    config:
      kvstore:
        type: sqlite
        namespace: null
        db_path: ${env.SQLITE_STORE_DIR:=~/.llama/distributions/ramalama}/huggingface_datasetio.db
  - provider_id: localfs
    provider_type: inline::localfs
    config:
      kvstore:
        type: sqlite
        namespace: null
        db_path: ${env.SQLITE_STORE_DIR:=~/.llama/distributions/ramalama}/localfs_datasetio.db
  eval:
  - provider_id: meta-reference
    provider_type: inline::meta-reference
    config:
      kvstore:
        type: sqlite
        namespace: null
        db_path: ${env.SQLITE_STORE_DIR:=~/.llama/distributions/ramalama}/meta_reference_eval.db
  inference:
  - provider_id: ramalama
    provider_type: remote::ramalama
    config:
      url: ${env.RAMALAMA_URL:=http://localhost:8080}
  - provider_id: sentence-transformers
    provider_type: inline::sentence-transformers
    config: {}
  post_training:
  - provider_id: huggingface
    provider_type: inline::huggingface
    config:
      checkpoint_format: huggingface
      distributed_backend: null
      device: cpu
  safety:
  - provider_id: llama-guard
    provider_type: inline::llama-guard
    config:
      excluded_categories: []
  scoring:
  - provider_id: basic
    provider_type: inline::basic
    config: {}
  - provider_id: llm-as-judge
    provider_type: inline::llm-as-judge
    config: {}
  - provider_id: braintrust
    provider_type: inline::braintrust
    config:
      openai_api_key: ${env.OPENAI_API_KEY:+}
  telemetry:
  - provider_id: meta-reference
    provider_type: inline::meta-reference
    config:
      service_name: ${env.OTEL_SERVICE_NAME:=llamastack}
      sinks: ${env.TELEMETRY_SINKS:=console,sqlite}
      sqlite_db_path: ${env.SQLITE_DB_PATH:=~/.llama/distributions/ramalama}/trace_store.db
  tool_runtime:
  - provider_id: brave-search
    provider_type: remote::brave-search
    config:
      api_key: ${env.BRAVE_SEARCH_API_KEY:+}
      max_results: 3
  - provider_id: tavily-search
    provider_type: remote::tavily-search
    config:
      api_key: ${env.TAVILY_SEARCH_API_KEY:+}
      max_results: 3
  - provider_id: rag-runtime
    provider_type: inline::rag-runtime
    config: {}
  - provider_id: model-context-protocol
    provider_type: remote::model-context-protocol
    config: {}
  - provider_id: wolfram-alpha
    provider_type: remote::wolfram-alpha
    config:
      api_key: ${env.WOLFRAM_ALPHA_API_KEY:+}
  vector_io:
  - provider_id: pgvector
    provider_type: remote::pgvector
    config:
      host: ${env.POSTGRES_HOST:=127.0.0.1}
      port: ${env.POSTGRES_PORT:=5432}
      db: ${env.PGVECTOR_DBNAME:=rag_blueprint}
      user: ${env.POSTGRES_USER:=postgres}
      password: ${env.POSTGRES_PASSWORD:=rag_password}
metadata_store:
  type: sqlite
  db_path: ${env.SQLITE_STORE_DIR:=~/.llama/distributions/ramalama}/registry.db
inference_store:
  type: sqlite
  db_path: ${env.SQLITE_STORE_DIR:=~/.llama/distributions/ramalama}/inference_store.db
models:
- metadata: {}
  model_id: ${env.INFERENCE_MODEL}
  provider_id: ramalama
  model_type: llm
- metadata:
    embedding_dimension: 384
  model_id: all-MiniLM-L6-v2
  provider_id: sentence-transformers
  model_type: embedding
shields: []
vector_dbs: []
datasets: []
scoring_fns: []
benchmarks: []
tool_groups:
- toolgroup_id: builtin::websearch
  provider_id: tavily-search
- toolgroup_id: builtin::rag
  provider_id: rag-runtime
- toolgroup_id: builtin::wolfram_alpha
  provider_id: wolfram-alpha
server:
  port: 8321
external_providers_dir: ${env.EXTERNAL_PROVIDERS_DIR:=~/.llama/providers.d}
EOF

    # Wait for PostgreSQL to be ready
    print_status "Waiting for PostgreSQL to be ready..."
    until podman exec "${POD_NAME}-pgvector" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
        sleep 2
    done
    
    # Wait for RamaLama to be ready
    print_status "Waiting for RamaLama model server to be ready..."
    until curl -s "http://localhost:$RAMALAMA_PORT/health" >/dev/null 2>&1; do
        sleep 5
    done
    
    # Create volume for llama-stack data
    podman volume create llama-stack-data || true
    
    podman run -d \
        --name "${POD_NAME}-stack" \
        --pod "$POD_NAME" \
        --env POSTGRES_HOST="127.0.0.1" \
        --env POSTGRES_PORT="$POSTGRES_PORT" \
        --env PGVECTOR_DBNAME="$POSTGRES_DB" \
        --env POSTGRES_USER="$POSTGRES_USER" \
        --env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --env INFERENCE_MODEL="tinyllama" \
        --env RAMALAMA_URL="http://127.0.0.1:$RAMALAMA_PORT" \
        --env SQLITE_STORE_DIR="/tmp/llama-stack" \
        --env TAVILY_SEARCH_API_KEY="${TAVILY_SEARCH_API_KEY:-}" \
        --volume "$TEMP_DIR/ramalama-run.yaml:/etc/ramalama/ramalama-run.yaml:ro" \
        --volume llama-stack-data:/tmp/llama-stack \
        quay.io/sallyom/ramalama-stack:latest
}

# Function to start UI
start_ui() {
    print_status "Starting Streamlit UI for Llama Stack"
    
    # Check if main pod is running
    if ! podman pod exists "$POD_NAME" 2>/dev/null; then
        print_error "Main pod $POD_NAME is not running. Please start it first with: $0 start"
        return 1
    fi
    
    # Stop existing UI container if it exists
    podman stop "${POD_NAME}-ui" 2>/dev/null || true
    podman rm "${POD_NAME}-ui" 2>/dev/null || true
    
    print_status "Adding Streamlit UI to the pod on port 8501"
    print_status "UI will be accessible at: http://localhost:8501"
    
    podman run -d \
        --name "${POD_NAME}-ui" \
        --pod "$POD_NAME" \
        -e LLAMA_STACK_ENDPOINT=http://localhost:8321 \
        quay.io/sallyom/ramalama-stack:ui
}

# Function to stop UI
stop_ui() {
    print_status "Stopping Streamlit UI"
    podman stop "${POD_NAME}-ui" 2>/dev/null || print_warning "UI container not running"
    podman rm "${POD_NAME}-ui" 2>/dev/null || true
}

# Function to show status
show_status() {
    print_status "Pod and container status:"
    podman pod ps --filter name="$POD_NAME"
    podman ps --filter pod="$POD_NAME"
    
    print_status "Service endpoints:"
    echo "  - PGVector Database: localhost:$POSTGRES_PORT"
    echo "  - RamaLama Model Server: localhost:$RAMALAMA_PORT"  
    echo "  - Llama Stack API: localhost:$LLAMA_STACK_PORT"
    echo "  - Streamlit UI: localhost:8501 (when started with start-ui)"
}

# Function to stop and remove everything
cleanup() {
    print_status "Stopping and removing pod: $POD_NAME"
    podman pod stop "$POD_NAME" || true
    podman pod rm "$POD_NAME" || true
    
    print_status "Removing volumes"
    podman volume rm pgvector-data || true
    podman volume rm llama-stack-data || true
    
    print_status "Cleaning up temporary files"
    if [[ "$IS_MACOS" == "true" ]]; then
        rm -rf "$TEMP_DIR"
    else
        rm -f /tmp/init-pgvector.sh /tmp/ramalama-run.yaml
    fi
}

# Function to show logs
show_logs() {
    local container_name="$1"
    if [ -z "$container_name" ]; then
        print_status "Available containers:"
        podman ps --filter pod="$POD_NAME" --format "table {{.Names}}"
        return
    fi
    
    podman logs -f "${POD_NAME}-${container_name}"
}

# Function to test the setup
test_setup() {
    print_status "Testing PGVector connection..."
    if podman exec "${POD_NAME}-pgvector" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" >/dev/null 2>&1; then
        echo "✓ PGVector connection successful"
    else
        echo "✗ PGVector connection failed"
        return 1
    fi
    
    print_status "Testing RamaLama model server..."
    if curl -s "http://localhost:$RAMALAMA_PORT/health" >/dev/null 2>&1; then
        echo "✓ RamaLama model server is responding"
    else
        echo "✗ RamaLama model server is not responding"
        return 1
    fi
    
    print_status "Testing Llama Stack API..."
    if curl -s "http://localhost:$LLAMA_STACK_PORT/health" >/dev/null 2>&1; then
        echo "✓ Llama Stack API is responding"
    else
        echo "✗ Llama Stack API is not responding"
        return 1
    fi
}

# Main execution
case "$1" in
    start)
        if check_pod_exists; then
            print_warning "Pod $POD_NAME already exists. Use 'stop' first or 'restart'"
            exit 1
        fi
        
        create_pod
        run_pgvector
        run_ramalama_model
        run_llama_stack
        
        print_status "Setup complete! All services are starting up."
        print_status "Use './podman-commands.sh status' to check the status"
        print_status "Use './podman-commands.sh test' to test the setup"
        print_status "Use './podman-commands.sh start-ui' to start the Streamlit UI"
        ;;
    start-ui)
        start_ui
        ;;
    stop-ui)
        stop_ui
        ;;
    stop)
        cleanup
        ;;
    restart)
        cleanup
        sleep 2
        $0 start
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$2"
        ;;
    test)
        test_setup
        ;;
    *)
        echo "Usage: $0 {start|start-ui|stop-ui|stop|restart|status|logs [container]|test}"
        echo ""
        echo "Commands:"
        echo "  start    - Create and start all containers in the pod"
        echo "  start-ui - Start the Streamlit UI (requires main pod to be running)"
        echo "  stop-ui  - Stop just the Streamlit UI container"
        echo "  stop     - Stop and remove the pod and all containers"
        echo "  restart  - Stop and restart the entire setup"
        echo "  status   - Show the current status of pod and containers"
        echo "  logs     - Show logs for a specific container (pgvector|ramalama|stack)"
        echo "  test     - Test the setup by checking all services"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 logs pgvector"
        echo "  $0 test"
        exit 1
        ;;
esac
