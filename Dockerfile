# Use Ubuntu 12.04 base image
FROM lawngnome/ubuntu:precise-20161209

# Fix repository URLs for the old Ubuntu version
RUN sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list \
    && sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list

# Install essential build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc-4.4 \
    g++-4.4 \
    bison \
    flex \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    texinfo \
    wget \
    xz-utils \
    libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies for manually building the MIPS cross-toolchain
RUN apt-get update && apt-get install -y make autoconf automake libtool

# Set working directory to /shared
WORKDIR /shared

# Ensure that binutils and gcc for MIPS are installed and properly configured
ENV PATH="/opt/cross/bin:${PATH}"

# Download and compile binutils for MIPS
WORKDIR /shared
RUN wget https://ftp.gnu.org/gnu/binutils/binutils-2.36.1.tar.gz --no-check-certificate \
    && tar -xzf binutils-2.36.1.tar.gz \
    && cd binutils-2.36.1 \
    && mkdir build && cd build \
    && ../configure --target=mips-linux-gnu --prefix=/opt/cross --disable-multilib \
    && make -j$(nproc) && make install

# Download and compile GCC for MIPS
WORKDIR /shared
RUN wget https://ftp.gnu.org/gnu/gcc/gcc-4.4.7/gcc-4.4.7.tar.gz --no-check-certificate \
    && tar -xzf gcc-4.4.7.tar.gz \
    && cd gcc-4.4.7 \
    && mkdir build && cd build \
    && ../configure --target=mips-linux-gnu --prefix=/opt/cross --enable-languages=c --disable-multilib \
    && make -j$(nproc) all-gcc && make install-gcc

# Set environment variables for kernel version
ENV KERNEL_VERSION=2.6.31
ENV KERNEL_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/linux-2.6.31.tar.bz2

# Set the working directory to /shared
WORKDIR /shared

# Download, extract, compile the Linux kernel, and create vmlinux and vmlinux-stripped
CMD /bin/bash -c '\
    if [ -f /shared/vmlinux ]; then \
        printf "vmlinux already exists in /shared. Skipping compilation.\n"; \
    else \
        if [ ! -f /shared/kernel.tar.bz2 ]; then \
            wget ${KERNEL_URL} --no-check-certificate -O /shared/kernel.tar.bz2; \
        fi; \
        if [ ! -d /shared/linux-${KERNEL_VERSION} ]; then \
            tar -xjf /shared/kernel.tar.bz2 -C /shared; \
            printf "Kernel source extracted to /shared/linux-${KERNEL_VERSION}\n"; \
        fi; \
        cd /shared/linux-${KERNEL_VERSION} && \
        make ARCH=mips CROSS_COMPILE=mips-linux-gnu- malta_defconfig && \
        # Modify the .config file to switch to Big-Endian
        sed -i "s/CONFIG_CPU_LITTLE_ENDIAN=y/# CONFIG_CPU_LITTLE_ENDIAN is not set/" .config && \
        echo "CONFIG_CPU_BIG_ENDIAN=y" >> .config && \
        printf "Configuration updated to Big-Endian\n" && \
        # Compile the kernel
        make ARCH=mips CROSS_COMPILE=mips-linux-gnu- V=1 vmlinux KCFLAGS="-march=mips32r2 -g -Wno-unused-variable -Wno-unused-but-set-variable" CFLAGS="-march=mips32r2 -g -Wno-unused-variable -Wno-unused-but-set-variable" 2>&1 | tee -a /shared/build.log && \
        cp /shared/linux-${KERNEL_VERSION}/vmlinux /shared/ && \
        cp /shared/linux-${KERNEL_VERSION}/vmlinux /shared/vmlinux-stripped && \
        mips-linux-gnu-strip /shared/vmlinux-stripped && \
        printf "Kernel vmlinux compiled and vmlinux-stripped created!\n"; \
        file /shared/vmlinux | tee -a /shared/build.log && \
        file /shared/vmlinux-stripped | tee -a /shared/build.log; \
    fi; \
    sleep infinity'

