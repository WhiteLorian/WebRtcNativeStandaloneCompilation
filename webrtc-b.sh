#!/usr/bin/env bash

# READ ME:

# THE GOAL
# Using WebRTC on our codebase that depends on boost (vc141-1.70.0) and openssl (vc140-1.1.1c) libraries.
# OS Windows x86 architecture. MSVS 2017 with dynamic runtime /MD.
# Local goal is to compile Peerconnection example (in our code base) see USAGE section.

# PRECONDITIONS
# Read and complete:
#  - Setting up Windows;
#  - Install depot_tools;
# by the link https://chromium.googlesource.com/chromium/src/+/master/docs/windows_build_instructions.md
#  - Create (using symlinks) openssl directory:
#  openssl
#    - x64 [openSslRoot]
#      - include
#      - lib
#    - x86 [openSslRoot]
#      - include
#      - lib

# COMPILATION
#  - Create new directory and put the script to it;
#  - Setup openSslRoot (below) to external OpenSSL directory;
#  - Run bash command line tool with admin rights;
#  - Run the script: ./webrtc-b.sh <revision>
#  - After message appears "Apply patch and press [Enter] key to proceed"
#    apply the patches src.diff and build.diff and press Enter twice

# USAGE
#  - the order of including LIB files matter. webrtc.lib must be on first place at least
#    must be placed before libssl.lib, libcrypto.lib and absl_time_zone.lib (the last one can be deleted)
#    This helps to avoid linkage issues;
#  - you can compile Release/Debug but you cannot run Debug version it just not run.

# see https://chromiumdash.appspot.com/releases?platform=Windows
# and https://chromiumdash.appspot.com/branches
# pages to find revision (stable I guess) and corresponding branch
# 89.0.4389.90 Mar 12 2021 - here revision = 4389

# check if the branch revision is passed to the script
if [[ $# -lt 1 ]]; then
    echo "Lack of argument: branch revision"
    exit
fi

# Find MSBuild 2019 (16)
vs16Path="$( cd "$( dirname "$vs2019_install" )" && pwd )"

msBuildPath16="$vs16Path/Professional/MSBuild/Current/Bin/MSBuild.exe"

isVs16=false

if [[ ! -e $msBuildPath16 ]]; then
        echo "Set env var: vs2019_install. Cannot find MSBuild path"
    else
        isVs16=true
        echo "vs2019_install path is found: $msBuildPath16"
fi
  
# Find MSBuild 2017 (15)
vs15Path="$( cd "$( dirname "$vs2017_install" )" && pwd )"

msBuildPath15="$vs15Path/Professional/MSBuild/15.0/Bin/MSBuild.exe"

isVs15=false

if [[ ! -e $msBuildPath15 ]]; then
        echo "Set env var: vs2017_install. Cannot find MSBuild path"
    else
        isVs15=true
        echo "vs2017_install path is found: $msBuildPath15"
fi

if [ "$isVs16" = false ] && [ "$isVs15" = false ]; then
    echo "Neither MSVS 2017 nor MSVS 2019 is found. Exit"
    exit
fi

if [ "$isVs16" = true ]; then
        msBuildPath="$msBuildPath16"
    else
        msBuildPath="$msBuildPath15"
fi

echo "Builder path: $msBuildPath"

# copy file
# $1: Source
# $2: Destination
function copyFile() {
    local src="$1"
    local dst="$2"
    
    if [[ -e $src ]]; then
        cp $src $dst
    else
        echo "File doesn't exest $src"
    fi
}

# create directory if doesn't exist
# $1: path to dir
function makeDir() {
    local pth="$1"
    
    if [[ ! -e $pth ]]; then
        mkdir -p $pth
    else
        echo "Dir path exists $pth"
    fi
}

# store root dir for the script
rootDir="$PWD"

# prefix for OUT directory
out="out"

makeDir $out
makeDir $out/lib

outResultDir="$rootDir/$out"

echo "============================================="
echo "Out result dir: $outResultDir"
echo "============================================="

# create include derictory
makeDir $outResultDir/include

# fetch WebRTC and sync
fetch --nohooks webrtc
gclient sync --with_branch_heads

# change directory to 'src'
pushd src >/dev/null

    git checkout branch-heads/$1
    
    # This is because the third_party is not consistent with the old version
    # after switching to the old version, and it is still the code of the 
    # original new version. At this time, just execute gclient sync. Therefore, 
    # git reset only changes a part of the local code, third_party does not change, 
    # and gclient sync makes the local code consistent with the remote version of the code.    
    gclient sync
    
    read -p "Apply patch and press [Enter] key to proceed"
    read -p "Are you sure?"
    
    # Platforms
    platforms=('Win32' 'x64')
    
    for pla in "${platforms[@]}"; do
    
        targetCpu=$([ "$pla" == "Win32" ] && echo "x86" || echo "x64")
        
        # Configurations
        configurations=('Debug' 'Release')
        
        for conf in "${configurations[@]}"; do
        
            isDebug=$([ "$conf" == "Debug" ] && echo "true" || echo "false")
            
            outDir="$out/$targetCpu/$conf"
            echo "Output dir: ./$outDir"
            
            outDirFull="$rootDir/$out/lib/$targetCpu/$conf"
            echo "Final output dir: $outDirFull"

            # If the following value is set to 'false' it means:
            #  - BoringSSL is NOT used but external OpenSSL
            #  - external OpenSSL path must be set 'sslRoot'
            # If the following value is set to 'true' it means:
            #  - BoringSSL is used
            #  - external path 'sslRoot' isn't necessary to set
            buildSsl=false
            
            # It must have 'lib' and 'include' subfolders (use symlinks)
            # d:\Rep\openssl\x86\include\openssl\ ..
            # d:\Rep\openssl\x86\lib\libcrypto.lib 
            # and etc.
            # the option works after applying src.patch
            # see details https://groups.google.com/a/chromium.org/g/gn-dev/c/h1aeSmPsxFo/m/SjcNRvfGBgAJ
            sslRoot="d:/Rep/openssl/$targetCpu"
            openSslRoot=""
            
            if [ "$buildSsl" != true ]; then
                openSslRoot="$sslRoot"
                echo "Not build OpenSSL, use external $openSslRoot"
            else
                echo "Build with BoringSSL"
            fi
            
            # create lib dirictories
            makeDir $rootDir/$out/lib/$targetCpu
            makeDir $rootDir/$out/lib/$targetCpu/$conf

            # build arguments
            args="is_debug=$isDebug use_rtti=true rtc_include_tests=false use_custom_libcxx=false target_cpu=\"$targetCpu\" rtc_build_ssl=$buildSsl rtc_ssl_root=\"$openSslRoot\" target_os=\"win\" target_winuwp_family=\"desktop\"  enable_iterator_debugging=$isDebug use_lld=false treat_warnings_as_errors=false"
            echo "Build args: $args"
            
            #build WebRTC
            gn.bat gen $outDir --args="$args"
            ninja -C $outDir
            
            # copy webrtc.lib to lib folder
            copyFile "./$outDir/obj/webrtc.lib" "$outDirFull/webrtc.lib"

            echo "============================================="
            echo "      Build third-party dependencies         "
            echo "============================================="

            # Third-party dependencies to build
            thirdParties=('third_party/abseil-cpp' 'third_party/jsoncpp/source')

            for thpPath in "${thirdParties[@]}"; do

                echo "path to source $thpPath"
            
                # change directory to a 'third_party' path
                pushd $thpPath >/dev/null
                
                    # create Build directory
                    buildDir="Build$targetCpu$conf"
                    makeDir $buildDir
                    
                    # change directory to Build directory
                    pushd $buildDir >/dev/null
                    
                        #-D CMAKE_CXX_FLAGS=" /D_ITERATOR_DEBUG_LEVEL=0" \
                        # create solution
                        cmake -G "Visual Studio 15 2017" -A $pla \
                            -DBUILD_TESTING=OFF \
                            -D CMAKE_CXX_FLAGS_RELEASE:STRING=" /MD /O2 /Ob2 /DNDEBUG /std:c++17 /D_ITERATOR_DEBUG_LEVEL=0" \
                            -D CMAKE_CXX_FLAGS_DEBUG:STRING=" /MDd /Zi /Ob0 /Od /RTC1 /std:c++17 /D_ITERATOR_DEBUG_LEVEL=2" \
                            -D JSONCPP_WITH_POST_BUILD_UNITTEST:BOOL=OFF \
                            -D JSONCPP_WITH_TESTS:BOOL=OFF \
                            -D _ITERATOR_DEBUG_LEVEL=0 \
                            ..
                        
                        slnPath=$(find . -path "*.sln")

                        echo "Build solution: $slnPath"
                        
                        # build solution
                        "$msBuildPath" $slnPath //p:Configuration=$conf,Platform=$pla
                        
                        # copy lib files for third-parties
                        find . -name '*.so' -o -name '*.dll' -o -name '*.lib' -o -name '*.a' -o -name '*.jar' | \
                            xargs -I '{}' cp '{}' $outDirFull

                    # return to a 'third_party' root directory
                    popd >/dev/null
                
                # return to 'src' directory
                popd >/dev/null
            
            done
            # end cycle for third-parties
        
        done
        # end cycle for configurations
    
    done
    # end cycle for platforms

echo "============================================="
echo "    Copy source files to include directory   "
echo "============================================="

# copy header files, skip 'third_party' and 'out' dir
find . -path './out' -prune -o -path './third_party' -prune -o \
    -type f \( -name '*.h' \) -print | xargs -I '{}' cp --parents '{}' $outResultDir/include

# Find and copy dependencies
# The following build dependencies were excluded: 
# gflags, ffmpeg, openh264, openmax_dl, winsdk_samples, yasm
find . -name '*.h' -o -name README -o -name LICENSE -o -name COPYING | \
grep './third_party' | \
grep -E 'abseil-cpp|boringssl|jsoncpp|libpng|libjpeg_turbo|libsrtp|libyuv|libvpx|opus|protobuf' | \
xargs -I '{}' cp --parents '{}' $outResultDir/include

# copy custom files
copyFile "./rtc_base/strings/json.cc" "$outResultDir/include/rtc_base/strings/json.cc"
copyFile "./test/vcm_capturer.cc" "$outResultDir/include/test/vcm_capturer.cc"
copyFile "./test/test_video_capturer.cc" "$outResultDir/include/test/test_video_capturer.cc"
copyFile "./api/jsep.cc" "$outResultDir/include/api/jsep.cc"
copyFile "./modules/audio_processing/agc2/rnn_vad/auto_correlation.cc" "$outResultDir/include/modules/audio_processing/agc2/rnn_vad/auto_correlation.cc"
copyFile "./third_party/protobuf/src/google/protobuf/implicit_weak_message.cc" "$outResultDir/include/third_party/protobuf/src/google/protobuf/implicit_weak_message.cc"
copyFile "./third_party/protobuf/src/google/protobuf/port_def.inc" "$outResultDir/include/third_party/protobuf/src/google/protobuf/port_def.inc"
copyFile "./third_party/protobuf/src/google/protobuf/port_undef.inc" "$outResultDir/include/third_party/protobuf/src/google/protobuf/port_undef.inc"
copyFile "./third_party/abseil-cpp/absl/flags/internal/flag_msvc.inc" "$outResultDir/include/third_party/abseil-cpp/absl/flags/internal/flag_msvc.inc"

# return to 'root' directory
popd >/dev/null
