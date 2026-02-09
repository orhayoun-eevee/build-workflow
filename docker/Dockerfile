FROM ubuntu:24.04

LABEL maintainer="eevee"
LABEL description="Helm chart validation framework - all tools in one image"

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    jq \
    python3 \
    python3-pip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Install Helm 3.16.3
RUN curl -fsSL https://get.helm.sh/helm-v3.16.3-linux-amd64.tar.gz -o helm.tar.gz \
    && tar -zxvf helm.tar.gz \
    && mv linux-amd64/helm /usr/local/bin/helm \
    && rm -rf helm.tar.gz linux-amd64 \
    && helm version

# Install helm-unittest plugin 0.7.2
RUN helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.7.2

# Install kubeconform 0.7.0
RUN wget -q https://github.com/yannh/kubeconform/releases/download/v0.7.0/kubeconform-linux-amd64.tar.gz \
    && tar -xzf kubeconform-linux-amd64.tar.gz \
    && mv kubeconform /usr/local/bin/kubeconform \
    && rm kubeconform-linux-amd64.tar.gz \
    && kubeconform -v

# Install chart-testing (ct) 3.12.0
RUN wget -q https://github.com/helm/chart-testing/releases/download/v3.12.0/chart-testing_3.12.0_linux_amd64.tar.gz \
    && tar -xzf chart-testing_3.12.0_linux_amd64.tar.gz \
    && mv ct /usr/local/bin/ct \
    && rm chart-testing_3.12.0_linux_amd64.tar.gz \
    && ct version

# Install yq 4.44.6
RUN wget -q https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_linux_amd64 -O /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    && yq --version

# Install kube-linter 0.7.0
RUN wget -q https://github.com/stackrox/kube-linter/releases/download/v0.7.0/kube-linter-linux.tar.gz \
    && tar -xzf kube-linter-linux.tar.gz \
    && mv kube-linter /usr/local/bin/kube-linter \
    && rm kube-linter-linux.tar.gz \
    && kube-linter version

# Install Python packages with pinned versions
# - yamllint: YAML formatting linter
# - checkov: IaC security scanner
# - yamale: YAML schema validator (required by chart-testing)
RUN pip3 install --no-cache-dir --break-system-packages \
    yamllint==1.35.1 \
    checkov==3.2.357 \
    yamale==5.2.1

# Verify installations
RUN echo "=== Tool versions ===" \
    && helm version --short \
    && kubeconform -v \
    && ct version \
    && yq --version \
    && kube-linter version \
    && yamllint --version \
    && checkov --version \
    && python3 -c "import yamale; print('yamale OK')"

# Trust all mounted git directories (Docker volume mounts change ownership)
RUN git config --global --add safe.directory '*'

ENTRYPOINT ["/bin/bash"]
