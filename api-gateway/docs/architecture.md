```mermaid
flowchart TD
    subgraph "Client"
        A[Client Application]
    end

    subgraph "HX API Gateway"
        B{Catch-All Route<br>@app.api_route("/{full_path:path}")}
        C[GatewayPipeline Instance]

        subgraph "Middleware Chain"
            D[1. SecurityMiddleware<br><i>Authenticates Request</i>]
            E[2. TransformMiddleware<br><i>Modifies Request/Response</i>]
            F[3. ExecutionMiddleware<br><i>Proxies to Backend</i>]
        end
    end

    subgraph "Backend Services"
        G[Upstream Service<br>(e.g., LiteLLM, Ollama)]
    end

    A -- HTTPS Request --> B
    B -- Instantiates --> C
    C -- process_request() --> D
    D -- next() --> E
    E -- next() --> F
    F -- httpx.AsyncClient.request() --> G
    G -- Backend Response --> F
    F -- Returns Response --> E
    E -- Returns Response --> D
    D -- Returns Response --> C
    C -- FastAPI Response --> A
```
