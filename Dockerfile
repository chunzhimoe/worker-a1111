# ---------------------------------------------------------------------------- #
#                         Stage 1: Download the models                         #
# ---------------------------------------------------------------------------- #
FROM alpine/git:2.36.2 as download

# 复制克隆脚本
COPY builder/clone.sh /clone.sh

# 克隆必要的代码仓库
RUN . /clone.sh taming-transformers https://github.com/CompVis/taming-transformers.git 24268930bf1dce879235a7fddd0b2355b84d7ea6 && \
    rm -rf data assets **/*.ipynb

RUN . /clone.sh stable-diffusion-stability-ai https://github.com/Stability-AI/stablediffusion.git 47b6b607fdd31875c9279cd2f4f16b92e4ea958e && \
    rm -rf assets data/**/*.png data/**/*.jpg data/**/*.gif

RUN . /clone.sh CodeFormer https://github.com/sczhou/CodeFormer.git c5b4593074ba6214284d6acd5f1719b6c5d739af && \
    rm -rf assets inputs

RUN . /clone.sh BLIP https://github.com/salesforce/BLIP.git 48211a1594f1321b00f14c9f7a5b4813144b2fb9 && \
    . /clone.sh k-diffusion https://github.com/crowsonkb/k-diffusion.git 5b3af030dd83e0297272d861c19477735d0317ec && \
    . /clone.sh clip-interrogator https://github.com/pharmapsychotic/clip-interrogator 2486589f24165c8e3b303f84e9dbbea318df83e8 && \
    . /clone.sh generative-models https://github.com/Stability-AI/generative-models 45c443b316737a4ab6e40413d7794a7f5657c19f

# 创建模型目录
RUN mkdir -p /models/Stable-diffusion && \
    mkdir -p /models/Lora

# 安装wget并下载模型
RUN apk add --no-cache wget && \
    # 下载基础模型到Stable-diffusion目录
    wget -q -O /models/Stable-diffusion/model.safetensors https://civitai.com/api/download/models/11745?type=Model&format=SafeTensor&size=full&fp=fp16 && \
    # 下载Lora模型 (替换YOUR_LORA_ID为实际的模型ID)
    wget -q -O /models/Lora/hanguo.safetensors https://civitai.com/api/download/models/31284?type=Model&format=SafeTensor&size=full&fp=fp16 && \
    wget -q -O /models/Lora/riben.safetensors https://civitai.com/api/download/models/34562?type=Model&format=SafeTensor&size=full&fp=fp16 && \
    wget -q -O /models/Lora/taiwan.safetensors https://civitai.com/api/download/models/52974?type=Model&format=SafeTensor && \
    wget -q -O /models/Lora/zhongguo.safetensors https://civitai.com/api/download/models/66172?type=Model&format=SafeTensor 

# ---------------------------------------------------------------------------- #
#                        Stage 3: Build the final image                        #
# ---------------------------------------------------------------------------- #
FROM python:3.10.9-slim as build_final_image

ARG SHA=5ef669de080814067961f28357256e8fe27544f4

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    LD_PRELOAD=libtcmalloc.so \
    ROOT=/stable-diffusion-webui \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 设置命令行参数
RUN export COMMANDLINE_ARGS="--skip-torch-cuda-test --precision full --no-half"
RUN export TORCH_COMMAND='pip install --pre torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.6'

# 安装系统依赖
RUN apt-get update && \
    apt install -y \
    fonts-dejavu-core rsync git jq moreutils aria2 wget libgoogle-perftools-dev procps libgl1 libglib2.0-0 && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && apt-get clean -y

# 安装PyTorch
RUN --mount=type=cache,target=/cache --mount=type=cache,target=/root/.cache/pip \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# 克隆stable-diffusion-webui
RUN --mount=type=cache,target=/root/.cache/pip \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git && \
    cd stable-diffusion-webui && \
    git reset --hard ${SHA}

# 创建必要的目录
RUN mkdir -p ${ROOT}/models/Stable-diffusion && \
    mkdir -p ${ROOT}/models/Lora

# 从下载阶段复制所有文件
COPY --from=download /repositories/ ${ROOT}/repositories/
COPY --from=download /models/Stable-diffusion/* ${ROOT}/models/Stable-diffusion/
COPY --from=download /models/Lora/* ${ROOT}/models/Lora/

RUN mkdir ${ROOT}/interrogate && cp ${ROOT}/repositories/clip-interrogator/data/* ${ROOT}/interrogate
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r ${ROOT}/repositories/CodeFormer/requirements.txt

# 安装Python依赖
COPY builder/requirements.txt /requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    pip install --upgrade -r /requirements.txt --no-cache-dir && \
    rm /requirements.txt

ADD src .

# 复制并运行缓存脚本
COPY builder/cache.py /stable-diffusion-webui/cache.py
RUN cd /stable-diffusion-webui && python cache.py --use-cpu=all --ckpt models/Stable-diffusion/model.safetensors

# 清理
RUN apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# 设置权限并指定启动命令
RUN chmod +x /start.sh
CMD /start.sh
