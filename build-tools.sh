#!/bin/bash

TOOLCHAIN_DIR=$(cd "`dirname \"$0\"`"; pwd)
TOP=$(cd ${TOOLCHAIN_DIR}/..; pwd)

# ====================================================================

CLEAN_BUILD=no
DEBUG_BUILD=no
BUILD_DIR=${TOP}/build
INSTALL_DIR=${TOP}/install
TARGET_TRIPLET=m32r-unknown-elf

# ====================================================================

# These are deliberately left blank, defaults are filled in below as
# appropriate.
JOBS=
LOAD=

# ====================================================================

function usage () {
    MSG=$1

    echo "${MSG}"
    echo
    echo "Usage: ./build-tools.sh [--build-dir <build_dir>]"
    echo "                        [--install-dir <install_dir>]"
    echo "                        [--clean]"
    echo "                        [--debug]"
    echo "                        [--jobs <count>] [--load <load>]"
    echo "                        [--single-thread]"

    exit 1
}

# Parse options
until
opt=$1
case ${opt} in
    --build-dir)
	shift
	BUILD_DIR=$(realpath -m $1)
	;;

    --install-dir)
	shift
	INSTALL_DIR=$(realpath -m $1)
	;;

    --jobs)
	shift
	JOBS=$1
	;;

    --load)
	shift
	LOAD=$1
	;;

    --single-thread)
	JOBS=1
	LOAD=1000
	;;

    --clean)
	CLEAN_BUILD=yes
	;;

    --debug)
	DEBUG_BUILD=yes
	;;

    ?*)
	usage "Unknown argument $1"
	;;

    *)
	;;
esac
[ "x${opt}" = "x" ]
do
    shift
done

set -u

# ====================================================================

BINUTILS_BUILD_DIR=${BUILD_DIR}/binutils
GDB_BUILD_DIR=${BUILD_DIR}/gdb
GCC_STAGE_1_BUILD_DIR=${BUILD_DIR}/gcc-stage1
GCC_STAGE_2_BUILD_DIR=${BUILD_DIR}/gcc-stage2
NEWLIB_BUILD_DIR=${BUILD_DIR}/newlib

INSTALL_PREFIX_DIR=${INSTALL_DIR}
INSTALL_SYSCONF_DIR=${INSTALL_DIR}/etc
INSTALL_LOCALSTATE_DIR=${INSTALL_DIR}/var

SYSROOT_DIR=${INSTALL_DIR}/${TARGET_TRIPLET}/sysroot
SYSROOT_HEADER_DIR=${SYSROOT_DIR}/usr

# Default parallellism
processor_count="`(echo processor; cat /proc/cpuinfo 2>/dev/null echo processor) \
           | grep -c processor`"
if [ -z "${JOBS}" ]; then JOBS=${processor_count}; fi
if [ -z "${LOAD}" ]; then LOAD=${processor_count}; fi
PARALLEL="-j ${JOBS} -l ${LOAD}"

INSTALL_DIR=${INSTALL_PREFIX_DIR}

# ====================================================================

echo "               Top: ${TOP}"
echo "         Toolchain: ${TOOLCHAIN_DIR}"
echo "            Target: ${TARGET_TRIPLET}"
echo "       Debug build: ${DEBUG_BUILD}"
echo "         Build Dir: ${BUILD_DIR}"
echo "       Install Dir: ${INSTALL_DIR}"

if [ "x${CLEAN_BUILD}" = "xyes" ]
then
    for T in `seq 5 -1 1`
    do
	echo -ne "\r       Clean Build: yes (in ${T} seconds)"
	sleep 1
    done
    echo -e "\r       Clean Build: yes                           "
    rm -fr ${BINUTILS_BUILD_DIR} ${GDB_BUILD_DIR} \
           ${GCC_STAGE_1_BUILD_DIR} ${NEWLIB_BUILD_DIR} \
           ${GCC_STAGE_2_BUILD_DIR}
else
    echo "       Clean Build: no"
fi

if [ "x${DEBUG_BUILD}" = "xyes" ]
then
    export CFLAGS="-g3 -O0"
    export CXXFLAGS="-g3 -O0"
fi

# ====================================================================

JOB_START_TIME=
JOB_TITLE=

SCRIPT_START_TIME=`date +%s`

LOGDIR=${TOP}/logs
if ! mkdir -p ${LOGDIR}
then
    echo "Failed to create log directory: ${LOGDIR}"
    exit 1
fi

LOGFILE=`mktemp -p ${LOGDIR} build-$(date +%F-%H%M)-XXXX.log`
if [ ! -w "${LOGFILE}" ]
then
    echo "Logfile is not writable: ${LOGFILE}"
    exit 1
fi

echo "          Log file: ${LOGFILE}"
echo "          Start at: "`date`
echo "          Parallel: ${PARALLEL}"
echo ""

if ! touch ${LOGFILE}
then
    echo "Failed to initialise logfile: ${LOGFILE}"
    exit 1
fi

# ====================================================================

# Defines: msg, error, times_to_time_string, job_start, job_done,
#          mkdir_and_enter, enter_dir, run_command
#
# Requires LOGFILE and SCRIPT_START_TIME environment variables to be
# set.
source common.sh

# ====================================================================
#                    Locations of all the source
# ====================================================================

BINUTILS_SOURCE_DIR=${TOP}/binutils-gdb
GDB_SOURCE_DIR=${TOP}/binutils-gdb
GCC_SOURCE_DIR=${TOP}/gcc
NEWLIB_SOURCE_DIR=${TOP}/newlib

# ====================================================================
#                Log git versions into the build log
# ====================================================================

job_start "Writing git versions to log file"
log_git_versions binutils "${BINUTILS_SOURCE_DIR}" \
                 gdb "${GDB_SOURCE_DIR}" \
                 gcc "${GCC_SOURCE_DIR}" \
                 newlib "${NEWLIB_SOURCE_DIR}"
job_done

# ====================================================================
#                   Build and install binutils
# ====================================================================

job_start "Building binutils"

mkdir_and_enter "${BINUTILS_BUILD_DIR}"

if ! run_command ${BINUTILS_SOURCE_DIR}/configure \
         --prefix=${INSTALL_PREFIX_DIR} \
         --sysconfdir=${INSTALL_SYSCONF_DIR} \
         --localstatedir=${INSTALL_LOCALSTATE_DIR} \
         --disable-gtk-doc \
         --disable-gtk-doc-html \
         --disable-doc \
         --disable-docs \
         --disable-documentation \
         --with-xmlto=no \
         --with-fop=no \
         --disable-multilib \
         --target=${TARGET_TRIPLET} \
         --with-sysroot=${SYSROOT_DIR} \
         --enable-poison-system-directories \
         --disable-tls \
         --disable-gdb \
         --disable-libdecnumber \
         --disable-readline \
         --disable-sim
then
    error "Failed to configure binutils"
fi

if ! run_command make ${PARALLEL}
then
    error "Failed to build binutils"
fi

if ! run_command make ${PARALLEL} install
then
    error "Failed to install binutils"
fi

job_done

# ====================================================================
#                   Build and install GDB and sim
# ====================================================================

job_start "Building GDB and sim"

mkdir_and_enter "${GDB_BUILD_DIR}"

if ! run_command ${GDB_SOURCE_DIR}/configure \
         --prefix=${INSTALL_PREFIX_DIR} \
         --sysconfdir=${INSTALL_SYSCONF_DIR} \
         --localstatedir=${INSTALL_LOCALSTATE_DIR} \
         --disable-gtk-doc \
         --disable-gtk-doc-html \
         --disable-doc \
         --disable-docs \
         --disable-documentation \
         --with-xmlto=no \
         --with-fop=no \
         --disable-multilib \
         --target=${TARGET_TRIPLET} \
         --with-sysroot=${SYSROOT_DIR} \
         --enable-poison-system-directories \
         --disable-tls \
         --disable-gprof \
         --disable-ld \
         --disable-gas \
         --disable-binutils
then
    error "Failed to configure GDB and sim"
fi

if ! run_command make ${PARALLEL}
then
    error "Failed to build GDB and sim"
fi

if ! run_command make ${PARALLEL} install
then
    error "Failed to install GDB and sim"
fi

job_done

# ====================================================================
#                Build and Install GCC (Stage 1)
# ====================================================================

job_start "Building stage 1 GCC"

mkdir_and_enter ${GCC_STAGE_1_BUILD_DIR}

if ! run_command ${GCC_SOURCE_DIR}/configure \
               --prefix="${INSTALL_PREFIX_DIR}" \
               --sysconfdir="${INSTALL_SYSCONF_DIR}" \
               --localstatedir="${INSTALL_LOCALSTATE_DIR}" \
               --disable-shared \
               --disable-static \
               --disable-gtk-doc \
               --disable-gtk-doc-html \
               --disable-doc \
               --disable-docs \
               --disable-documentation \
               --with-xmlto=no \
               --with-fop=no \
               --target=${TARGET_TRIPLET} \
               --with-sysroot=${SYSROOT_DIR} \
               --disable-__cxa_atexit \
               --with-gnu-ld \
               --disable-libssp \
               --disable-multilib \
               --enable-target-optspace \
               --disable-libsanitizer \
               --disable-tls \
               --disable-libmudflap \
               --disable-threads \
               --disable-libquadmath \
               --disable-libgomp \
               --without-isl \
               --without-cloog \
               --disable-decimal-float \
               --enable-languages=c \
               --without-headers \
               --with-newlib \
               --disable-largefile \
               --disable-nls \
               --enable-checking=yes
then
    error "Failed to configure GCC (stage 1)"
fi

if ! run_command make ${PARALLEL} all-gcc
then
    error "Failed to build GCC (stage 1)"
fi

if ! run_command make ${PARALLEL} install-gcc
then
    error "Failed to install GCC (stage 1)"
fi

job_done

# ====================================================================
#                   Build and install newlib
# ====================================================================

job_start "Building newlib"

# Add Binutils and GCC to path to build newlib
export PATH=${INSTALL_PREFIX_DIR}/bin:$PATH

mkdir_and_enter "${NEWLIB_BUILD_DIR}"

if ! run_command ${NEWLIB_SOURCE_DIR}/configure \
         --prefix=${INSTALL_PREFIX_DIR} \
         --sysconfdir=${INSTALL_SYSCONF_DIR} \
         --localstatedir=${INSTALL_LOCALSTATE_DIR} \
         --target=${TARGET_TRIPLET} \
         --with-sysroot=${SYSROOT_DIR}
then
    error "Failed to configure newlib"
fi

if ! run_command make ${PARALLEL}
then
    error "Failed to build newlib"
fi

if ! run_command make ${PARALLEL} install
then
    error "Failed to install newlib"
fi

job_done

# ====================================================================
#                Build and Install GCC (Stage 2)
# ====================================================================

job_start "Building stage 2 GCC"

mkdir_and_enter ${GCC_STAGE_2_BUILD_DIR}

if ! run_command ${GCC_SOURCE_DIR}/configure \
           --prefix="${INSTALL_PREFIX_DIR}" \
           --sysconfdir="${INSTALL_SYSCONF_DIR}" \
           --localstatedir="${INSTALL_LOCALSTATE_DIR}" \
           --disable-shared \
           --enable-static \
           --disable-gtk-doc \
           --disable-gtk-doc-html \
           --disable-doc \
           --disable-docs \
           --disable-documentation \
           --with-xmlto=no \
           --with-fop=no \
           --target=${TARGET_TRIPLET} \
           --with-sysroot=${SYSROOT_DIR} \
           --disable-__cxa_atexit \
           --with-gnu-ld \
           --disable-libssp \
           --disable-multilib \
           --enable-target-optspace \
           --disable-libsanitizer \
           --disable-tls \
           --disable-libmudflap \
           --disable-threads \
           --disable-libquadmath \
           --disable-libgomp \
           --without-isl \
           --without-cloog \
           --disable-decimal-float \
           --enable-languages=c,c++ \
           --with-newlib \
           --disable-largefile \
           --disable-nls \
           --enable-checking=yes \
           --with-build-time-tools=${INSTALL_PREFIX_DIR}/${TARGET_TRIPLET}/bin
then
    error "Failed to configure GCC (stage 2)"
fi

if ! run_command make ${PARALLEL} all
then
    error "Failed to build GCC (stage 2)"
fi

if ! run_command make ${PARALLEL} install
then
    error "Failed to install GCC (stage 2)"
fi

job_done

# ====================================================================
#                           Finished
# ====================================================================

all_finished
