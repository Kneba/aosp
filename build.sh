#!/usr/bin/env bash

#
# Copyright (C) 2023-2026 Kneba <abenkenary3@gmail.com>
#

msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
}

cdir() {
	cd "$1" 2>/dev/null || \
		err "The directory $1 doesn't exists !"
}

##------------------------------------------------------##
##----------Basic Informations, COMPULSORY--------------##

# Main
MainPath="$(pwd)"
ClangPath="${MainPath}/clang"

# Identity
ANDRVER=11-16
KERNELNAME=perf
CODENAME=plus
BASE=android13-4.19-sdm660

# Build dtbo.img (1 = Yes, 0 = No)
INCLUDE_DTBO=0

# Show manufacturer info
MANUFACTURERINFO="ASUSTek Computer Inc."
DEVICE=X00TD

# Clone Kernel Source
echo " "
msg "|| Cloning Kernel Source ||"
git clone --depth=1 https://github.com/sotodrom/kernel_asus_sdm660-4.19 -b 16 --single-branch kernel

# Clone AOSP Clang
[[ "$(pwd)" != "${MainPath}" ]] && cd "${MainPath}"
rm -rf $ClangPath/*
mkdir -p $ClangPath

msg "|| Cloning AOSP Clang ||"
## clang 21 ##
wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/ebcc6c3bef363bc539ea39f45b6abae1dce6ff1a/clang-r574158.tar.gz -O "clang-r574158.tar.gz"
tar -xf clang-r574158.tar.gz -C $ClangPath

##------------------------------------------------------##
##---------Do Not Touch Anything Beyond This------------##

# Prepared
KERNEL_ROOTDIR=$(pwd)/kernel 
export KBUILD_BUILD_USER="queen" 
export KBUILD_BUILD_HOST=$(cat /etc/hostname) 
IMAGE=$KERNEL_ROOTDIR/out/arch/arm64/boot/Image.gz-dtb
DTBO_IMAGE=$KERNEL_ROOTDIR/out/arch/arm64/boot/dtbo.img

CLANG_VER="$("$ClangPath"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
LLD_VER="$("$ClangPath"/bin/ld.lld --version | head -n 1)"
export KBUILD_COMPILER_STRING="$CLANG_VER with $LLD_VER"
DATE=$(TZ=Asia/Jakarta date +"%d%m%Y")
DATE2=$(TZ=Asia/Jakarta date +"%d%m%Y-%H%M")
DATE3=$(TZ=Asia/Jakarta date +"%d %b %Y, %H:%M %Z")
START=$(date +"%s")

#sed -i 's/.*CONFIG_DEBUG_INFO=.*/CONFIG_DEBUG_INFO=n/g' $KERNEL_ROOTDIR/arch/arm64/configs/vendor/asus/X00TD_defconfig

# Java
command -v java > /dev/null 2>&1

# Check Kernel Version
KERVER=$(cd $KERNEL_ROOTDIR; make kernelversion)

# The name of the Kernel, to name the ZIP
ZIPNAME="$KERNELNAME-$CODENAME-$KERVER"

# Telegram API
export BOT_MSG_URL="https://api.telegram.org/bot$TG_TOKEN/sendMessage"
export BOT_BUILD_URL="https://api.telegram.org/bot$TG_TOKEN/sendDocument"

# Telegram messaging
tg_post_msg() {
  curl -s -X POST "$BOT_MSG_URL" -d chat_id="$TG_CHAT_ID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=html" \
    -d text="$1"
}

# Compiler
compile(){
    cd ${KERNEL_ROOTDIR}
    curl -LSs "https://raw.githubusercontent.com/Sorayukii/KernelSU-Next/stable/kernel/setup.sh" | bash -s hookless

    export HASH_HEAD=$(git rev-parse --short HEAD)
    export COMMIT_HEAD=$(git log --oneline -1)
    export PATH="${ClangPath}/bin:$PATH"
    export LD_LIBRARY_PATH="${ClangPath}/lib"
    export LLVM_IAS=1
    export LLVM=1

    msg "|| Compile starting ||"
    tg_post_msg "<b>🚀 Compile Started:</b> <code>$KERNELNAME</code> for <code>$DEVICE</code>\n<b>⚙️ Compiler:</b> <code>$CLANG_VER</code>"

    rm -f error.log
    make -j$(nproc) vendor/asus/X00TD_defconfig \
    ARCH=arm64 \
    O=out 2>&1 | tee -a error.log
    
    make -j$(nproc) ARCH=arm64 SUBARCH=ARM64 O=out \
        LLVM=1 \
        CC=${ClangPath}/bin/clang 2>&1 | tee -a error.log

    if ! [ -a "$IMAGE" ]; then
        finerr
        exit 1
    fi

cd "$KERNEL_ROOTDIR"
    rm -rf AnyKernel
    git clone --depth=1 https://github.com/texascake/AnyKernel3 -b 4.19 AnyKernel
    
    cp $IMAGE AnyKernel/
    
    # Optional Logic for DTBO
    if [ "$INCLUDE_DTBO" -eq 1 ]; then
        msg "|| Include dtbo.img in the zip... ||"
        if [ -f "$DTBO_IMAGE" ]; then
            cp "$DTBO_IMAGE" AnyKernel/
        elif [ -f "$KERNEL_ROOTDIR/out/dtbo.img" ]; then
            cp "$KERNEL_ROOTDIR/out/dtbo.img" AnyKernel/
        else
            err "Warning: INCLUDE_DTBO=1, but dtbo.img file not found!"
        fi
    else
        msg "|| Skipping dtbo.img (INCLUDE_DTBO=0) ||"
    fi
}

# Push kernel to telegram
function push() {
    cd "$KERNEL_ROOTDIR"/AnyKernel
    curl -F document=@"$ZIP_FINAL.zip" "$BOT_BUILD_URL" \
        -F chat_id="$TG_CHAT_ID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html" \
        -F caption="✅<b>Build Done</b>
        - <code>$((DIFF / 60)) minute(s) $((DIFF % 60)) second(s) </code>
        <b>Ⓜ MD5: </b>
        - <code>$MD5CHECK</code>
        <b>📅 Build Date: </b>
        - <code>$DATE</code>
        <b>🐧 Linux Version: </b>
        - <code>$KERVER</code>
        <b>💿 Compiler: </b>
        - <code>$KBUILD_COMPILER_STRING</code>
        <b>📱 Device: </b>
        - <code>($MANUFACTURERINFO $DEVICE)</code>
        <b>🆑 Changelog: </b>
        - <code>$COMMIT_HEAD</code>"
}

# Find Error
function finerr() {
    curl -F document=@error.log "$BOT_BUILD_URL" \
        -F "chat_id=$TG_CHAT_ID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html" \
        -F "caption=<b>⛔ Build Error detected!</b> - <code>$((DIFF / 60)) minute(s) $((DIFF % 60)) second(s)... </code>"
    exit 1
}

# Zipping
function zipping() {
	cd "$KERNEL_ROOTDIR"/AnyKernel || exit 1
	zip -r9 $ZIPNAME-"$DATE" * -x .git README.md ./*placeholder .gitignore zipsigner* *.zip
 
	## Prepare a final zip variable
	ZIP_FINAL="$ZIPNAME-$DATE"

	msg "|| Signing Zip ||"
	tg_post_msg "<code>🔑 Signing Zip file with AOSP keys..</code>"

	mv $ZIP_FINAL* kernel.zip
	curl -sLo zipsigner-3.0-dexed.jar https://github.com/Magisk-Modules-Repo/zipsigner/raw/master/bin/zipsigner-3.0-dexed.jar
	java -jar zipsigner-3.0-dexed.jar kernel.zip kernel-signed.zip
	ZIP_FINAL="$ZIP_FINAL-signed"
 	mv kernel-signed.zip $ZIP_FINAL.zip
	MD5CHECK=$(md5sum "$ZIP_FINAL.zip" | cut -d' ' -f1)
}

compile
zipping
END=$(date +"%s")
DIFF=$(($END - $START))
push
