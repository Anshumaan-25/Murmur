# Third-party components

The application links operating-system frameworks and the system SQLite library. No reference application code or assets are included. Optional local inference engines and their license notices will be recorded when selected; their build products and models remain outside version control.

Optional speech decoder: whisper.cpp, MIT license. Runtime notice is copied from the fetched engine source into the application resources during packaging. Engine source remains in the ignored project build directory. Model: small English decoder, revision and SHA-256 recorded in the local download manifest.

Optional text decoder: llama.cpp, MIT license. Instruction weights: Qwen2.5 1.5B Instruct, Apache-2.0. The model and engine notices accompany the optional bundled resources. Download manifests preserve the exact revisions and hashes. No code from either engine is incorporated into the application source files.
