FROM scratch

LABEL name="openshift-layered-ai/skills" \
      version="1.23" \
      release="1" \
      cpe="cpe:/a:redhat:openshift_gitops:1.23::el9" \
      License="MIT" \
      distribution-scope="authoritative-source-only" \
      url="https://github.com/redhat-developer/agentic-skills" \
      vendor="Red Hat, Inc." \
      com.redhat.component="agentic-skills-container" \
      com.redhat.delivery.appregistry="false" \
      upstream-vcs-type="git" \
      io.openshift.expose-services="" \
      io.openshift.tags="openshift,gitops,agent-skills" \
      maintainer="OpenShift GitOps Team" \
      summary="Agent skills for Red Hat OpenShift layered products" \
      description="Agent skills for Red Hat OpenShift layered products (Argo CD, Argo Rollouts), packaged as an OCI content image consumed by AgenticRuns." \
      io.k8s.display-name="OpenShift Agent Skills" \
      io.k8s.description="Agent skills for Red Hat OpenShift layered products."

COPY skills/ /skills/
