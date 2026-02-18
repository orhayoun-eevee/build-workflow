FROM ubuntu:24.04

LABEL maintainer="eevee"
LABEL description="Helm chart validation framework - all tools in one image"

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive
ENV HELM_VERSION=3.20.0
ENV HELM_SHA256=dbb4c8fc8e19d159d1a63dda8db655f9ffa4aac1b9a6b188b34a40957119b286
ENV HELM_UNITTEST_VERSION=0.8.2
ENV KUBECONFORM_VERSION=0.7.0
ENV KUBECONFORM_SHA256=c31518ddd122663b3f3aa874cfe8178cb0988de944f29c74a0b9260920d115d3
ENV CT_VERSION=3.14.0
ENV CT_SHA256=d16f0583616885423826241164ce1f6589c6fe5332fa74f374ebd2bd3cb3fe1f
ENV YQ_VERSION=4.52.4
ENV YQ_SHA256=0c4d965ea944b64b8fddaf7f27779ee3034e5693263786506ccd1c120f184e8c
ENV KUBE_LINTER_VERSION=0.8.1
ENV KUBE_LINTER_SHA256=49629abaf0ae3283e9437214a2bea4bf4029008744e05471c85dd3872464f50b

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

# Install Helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -o helm.tar.gz \
    && echo "${HELM_SHA256}  helm.tar.gz" | sha256sum -c - \
    && tar -zxvf helm.tar.gz \
    && mv linux-amd64/helm /usr/local/bin/helm \
    && rm -rf helm.tar.gz linux-amd64 \
    && helm version

# Install helm-unittest plugin
RUN helm plugin install https://github.com/helm-unittest/helm-unittest --version "v${HELM_UNITTEST_VERSION}"

# Install kubeconform
RUN wget -q "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" \
    && echo "${KUBECONFORM_SHA256}  kubeconform-linux-amd64.tar.gz" | sha256sum -c - \
    && tar -xzf kubeconform-linux-amd64.tar.gz \
    && mv kubeconform /usr/local/bin/kubeconform \
    && rm kubeconform-linux-amd64.tar.gz \
    && kubeconform -v

# Install chart-testing (ct)
RUN wget -q "https://github.com/helm/chart-testing/releases/download/v${CT_VERSION}/chart-testing_${CT_VERSION}_linux_amd64.tar.gz" \
    && echo "${CT_SHA256}  chart-testing_${CT_VERSION}_linux_amd64.tar.gz" | sha256sum -c - \
    && tar -xzf "chart-testing_${CT_VERSION}_linux_amd64.tar.gz" \
    && mv ct /usr/local/bin/ct \
    && rm "chart-testing_${CT_VERSION}_linux_amd64.tar.gz" \
    && ct version

# Install yq
RUN wget -q "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" -O /usr/local/bin/yq \
    && echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c - \
    && chmod +x /usr/local/bin/yq \
    && yq --version

# Install kube-linter
RUN wget -q "https://github.com/stackrox/kube-linter/releases/download/v${KUBE_LINTER_VERSION}/kube-linter-linux.tar.gz" \
    && echo "${KUBE_LINTER_SHA256}  kube-linter-linux.tar.gz" | sha256sum -c - \
    && tar -xzf kube-linter-linux.tar.gz \
    && mv kube-linter /usr/local/bin/kube-linter \
    && rm kube-linter-linux.tar.gz \
    && kube-linter version

# Install Python packages with pinned versions
# - yamllint: YAML formatting linter
# - checkov: IaC security scanner
# - yamale: YAML schema validator (required by chart-testing)
RUN pip3 install --no-cache-dir --break-system-packages \
    yamllint==1.38.0 \
    checkov==3.2.504 \
    yamale==5.3.0

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
