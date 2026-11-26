FROM scratch

LABEL name="openshift-layered-ai/skills" \
      version="1.23" \
      release="1" \
      com.redhat.component="agentic-skills-container" \
      maintainer="OpenShift GitOps Team" \
      summary="Agent skills for Red Hat OpenShift layered products" \
      description="Agent skills for Red Hat OpenShift layered products (Argo CD, Argo Rollouts), packaged as an OCI content image consumed by AgenticRuns." \
      io.k8s.display-name="OpenShift Agent Skills" \
      io.k8s.description="Agent skills for Red Hat OpenShift layered products."

COPY skills/ /skills/
