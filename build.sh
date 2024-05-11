#!/usr/bin/env bash
#
# Copyright (C) 2023-2024 Kneba <abenkenary3@gmail.com>
#

#
# Function to show an informational message
#

#set -e

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
GCCaPath="${MainPath}/GCC64"
GCCbPath="${MainPath}/GCC32"

# Identity
KERNELNAME=TheOneMemory
CODENAME=Hayzel
VARIANT=HMP
BASE=longterm

# The name of the Kernel, to name the ZIP
ZIPNAME="$KERNELNAME-14-4-4"

# Show manufacturer info
MANUFACTURERINFO="ASUSTek Computer Inc."

# Clone Kernel Source
echo " "
msg "|| Cloning Kernel Source ||"
git clone --depth=1 --recursive https://$USERNAME:$TOKEN@github.com/Tiktodz/android_kernel_asus_sdm636 -b 14-ksu kernel

# Clone AOSP Clang
[[ "$(pwd)" != "${MainPath}" ]] && cd "${MainPath}"
rm -rf $ClangPath/*
mkdir $ClangPath

msg "|| Cloning AOSP Clang ||"
#git clone --depth=1 https://gitlab.com/ImSurajxD/clang-r450784d -b master $ClangPath
wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/master/clang-r510928.tar.gz -O "clang-r510928.tar.gz"
tar -xf clang-r510928.tar.gz -C $ClangPath

# Clone GCC
rm -rf $GCCaPath/*
rm -rf $GCCbPath/*
mkdir $GCCaPath
mkdir $GCCbPath
msg "|| Cloning AOSP GCC ||"
wget -q https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz -O "gcc64.tar.gz"
tar -xf gcc64.tar.gz -C $GCCaPath
wget -q https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz -O "gcc32.tar.gz"
tar -xf gcc32.tar.gz -C $GCCbPath

##------------------------------------------------------##
##---------Do Not Touch Anything Beyond This------------##

# Prepared
KERNEL_ROOTDIR=$(pwd)/kernel # IMPORTANT ! Fill with your kernel source root directory.
export LD=ld.lld
export HOSTLD=ld.lld
export KBUILD_BUILD_USER=queen # Change with your own name or else.
IMAGE=$KERNEL_ROOTDIR/out/arch/arm64/boot/Image.gz-dtb
CLANG_VER="$("$ClangPath"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
LLD_VER="$("$ClangPath"/bin/ld.lld --version | head -n 1)"
export KBUILD_COMPILER_STRING="$CLANG_VER with $LLD_VER"
DATE=$(TZ=Asia/Jakarta date +"%Y%m%d-%H%M")
START=$(date +"%s")

# Java
command -v java > /dev/null 2>&1

# Check Kernel Version
KERVER=$(cd $KERNEL_ROOTDIR; make kernelversion)

# Telegram
export BOT_MSG_URL="https://api.telegram.org/bot$TG_TOKEN/sendMessage"
export BOT_BUILD_URL="https://api.telegram.org/bot$TG_TOKEN/sendDocument"

tg_post_build() {
    #Post MD5Checksum alongwith for easeness
    MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)

    #Show the Checksum alongwith caption
    curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
    -F chat_id="$2"  \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=html" \
    -F caption="$3 | <b>MD5 Checksum : </b><code>$MD5CHECK</code>"  
}

# Telegram messaging
tg_post_msg() {
  curl -s -X POST "$BOT_MSG_URL" -d chat_id="$TG_CHAT_ID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=html" \
    -d text="$1"
}
# Speed up build process
MAKE="./makeparallel"
# Compiler
compile(){
cd ${KERNEL_ROOTDIR}
export HASH_HEAD=$(git rev-parse --short HEAD)
export COMMIT_HEAD=$(git log --oneline -1)
msg "|| Compile starting ||"
make -j$(nproc) O=out ARCH=arm64 X00TD_defconfig
make -j$(nproc) ARCH=arm64 O=out \
    LD_LIBRARY_PATH="${ClangPath}/lib64:${LD_LIBRARY_PATH}" \
    PATH=$ClangPath/bin:$GCCaPath/bin:$GCCbPath/bin:/usr/bin:${PATH} \
    CC=${ClangPath}/bin/clang \
    NM=${ClangPath}/bin/llvm-nm \
    CXX=${ClangPath}/bin/clang++ \
    AR=${ClangPath}/bin/llvm-ar \
    STRIP=${ClangPath}/bin/llvm-strip \
    OBJCOPY=${ClangPath}/bin/llvm-objcopy \
    OBJDUMP=${ClangPath}/bin/llvm-objdump \
    OBJSIZE=${ClangPath}/bin/llvm-size \
    READELF=${ClangPath}/bin/llvm-readelf \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    HOSTAR=${ClangPath}/bin/llvm-ar \
    HOSTCC=${ClangPath}/bin/clang \
    HOSTCXX=${ClangPath}/bin/clang++

   if ! [ -a "$IMAGE" ]; then
	finerr
	exit 1
   fi
   git clone --depth=1 https://github.com/Tiktodz/AnyKernel3 -b 44 AnyKernel
   cp $IMAGE AnyKernel
}
# Push kernel to telegram
function push() {
    cd AnyKernel
    curl -F document=@"$ZIP_FINAL.zip" "$BOT_BUILD_URL" \
        -F chat_id="$TG_CHAT_ID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html" \
        -F caption="✅<b>Build Done</b>
        -<code>$((DIFF / 60)) minute(s) $((DIFF % 60)) second(s)... </code>
        <b>📅 Build Date: </b>
        -<code>$DATE</code>
        <b>🐧 Linux Version: </b>
        -<code>$KERVER</code>
         <b>💿 Compiler: </b>
        -<code>$KBUILD_COMPILER_STRING</code>
        <b>📱 Device: </b>
        -<code>($MANUFACTURERINFO)</code>
        <b>🆑 Changelog: </b>
        -<code>$COMMIT_HEAD</code>"
}
# Find Error
function finerr() {
    curl -s -X POST "$BOT_MSG_URL" \
        -d chat_id="$TG_CHAT_ID" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=markdown" \
        -d text="❌ Tetap menyerah...Pasti bisa!!!"
    exit 1
}
# Zipping
function zipping() {
	cd AnyKernel || exit 1
	zip -r9 $ZIPNAME-"$DATE" * -x .git README.md placeholder .gitignore zipsigner* *.zip
 
	## Prepare a final zip variable
	ZIP_FINAL="$ZIPNAME-$DATE"

	msg "|| Signing Zip ||"
	tg_post_msg "<code>🔑 Signing Zip file with AOSP keys..</code>"

	curl -sLo zipsigner-3.0.jar https://github.com/Magisk-Modules-Repo/zipsigner/raw/master/bin/zipsigner-3.0-dexed.jar
	java -jar zipsigner-3.0.jar "$ZIP_FINAL".zip "$ZIP_FINAL"-signed.zip
	ZIP_FINAL="$ZIP_FINAL-signed"
	cd ..
}

compile
zipping
END=$(date +"%s")
DIFF=$(($END - $START))
push
