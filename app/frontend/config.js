// Runtime configuration for the frontend.
// In Docker/Kubernetes this file gets overwritten (via envsubst/ConfigMap) so the
// same static build can point at different backend URLs per environment.
window.CLOUDFORGE_API_BASE = "http://localhost:8000";
