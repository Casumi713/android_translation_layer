cmake_minimum_required(VERSION 3.16)
project(android_translation_layer_unified)

# Build configuration
set(BUILD_DIR "${CMAKE_BINARY_DIR}")
set(INSTALL_PREFIX "${BUILD_DIR}/install")

# Auto-detect JAVA_HOME (works on Debian/Ubuntu/Fedora)
if(DEFINED ENV{JAVA_HOME} AND NOT "$ENV{JAVA_HOME}" STREQUAL "")
    set(JAVA_HOME "$ENV{JAVA_HOME}")
    message(STATUS "JAVA_HOME from environment: ${JAVA_HOME}")
else()
    # Find java and derive JAVA_HOME
    find_program(JAVA_BIN java)
    if(JAVA_BIN)
        get_filename_component(JAVA_HOME_REAL "${JAVA_BIN}" REALPATH)
        # Resolve: /usr/lib/jvm/java-21-openjdk-<arch>/bin/java → /usr/lib/jvm/java-21-openjdk-<arch>
        get_filename_component(JAVA_HOME "${JAVA_HOME_REAL}" DIRECTORY)
        get_filename_component(JAVA_HOME "${JAVA_HOME}" DIRECTORY)
        message(STATUS "JAVA_HOME auto-detected: ${JAVA_HOME}")
    else()
        # Fallback: try common paths
        foreach(_jvmdir /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-21-openjdk-amd64 /usr/lib/jvm/java-21-openjdk-x86_64 /usr/lib/jvm/default-java)
            if(EXISTS "${_jvmdir}/bin/javac")
                set(JAVA_HOME "${_jvmdir}")
                break()
            endif()
        endforeach()
        if(NOT JAVA_HOME)
            message(FATAL_ERROR "Java 21 JDK not found. Set JAVA_HOME or install openjdk-21-jdk.")
        endif()
        message(STATUS "JAVA_HOME fallback: ${JAVA_HOME}")
    endif()
endif()
set(BIN_DIR "${BUILD_DIR}/bin")
set(LIB_DIR "${BUILD_DIR}/lib")
set(INCLUDE_DIR "${BUILD_DIR}/include")
set(PKGCONFIG_DIR "${LIB_DIR}/pkgconfig")
set(THIRDPARTY_DIR "${CMAKE_SOURCE_DIR}/thirdparty")

# Number of parallel jobs
include(ProcessorCount)
ProcessorCount(NPROC)
if(NPROC EQUAL 0)
    set(NPROC 4)
endif()

# Create output directories
file(MAKE_DIRECTORY ${BIN_DIR})
file(MAKE_DIRECTORY ${LIB_DIR})
file(MAKE_DIRECTORY ${INCLUDE_DIR})
file(MAKE_DIRECTORY ${PKGCONFIG_DIR})
file(MAKE_DIRECTORY "${LIB_DIR}/art")
file(MAKE_DIRECTORY "${LIB_DIR}/java")
file(MAKE_DIRECTORY "${LIB_DIR}/java/dex/art")
file(MAKE_DIRECTORY "${LIB_DIR}/java/dex/art/natives")

message(STATUS "Build directory: ${BUILD_DIR}")
message(STATUS "Install prefix: ${INSTALL_PREFIX}")
message(STATUS "Binary directory: ${BIN_DIR}")
message(STATUS "Library directory: ${LIB_DIR}")
message(STATUS "Parallel jobs: ${NPROC}")

# =============================================================================
# Step 1: Build wolfSSL
# =============================================================================
set(WOLFSSL_DIR "${THIRDPARTY_DIR}/wolfssl")
set(WOLFSSL_BUILD_DIR "${BUILD_DIR}/wolfssl_build")

add_custom_command(
    OUTPUT ${WOLFSSL_BUILD_DIR}/.built
    COMMAND ${CMAKE_COMMAND} -E make_directory ${WOLFSSL_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E chdir ${WOLFSSL_DIR} autoreconf -i
    COMMAND ${CMAKE_COMMAND} -E chdir ${WOLFSSL_BUILD_DIR} ${WOLFSSL_DIR}/configure
        --prefix=${INSTALL_PREFIX}
        --libdir=${LIB_DIR}
        --enable-shared
        --disable-opensslall
        --disable-opensslextra
        --enable-aescbc-length-checks
        --enable-curve25519
        --enable-ed25519
        --enable-ed25519-stream
        --enable-oldtls
        --enable-base64encode
        --enable-tlsx
        --enable-scrypt
        --disable-examples
        --enable-crl
        --enable-jni
        --enable-sessioncerts
    COMMAND ${CMAKE_COMMAND} -E chdir ${WOLFSSL_BUILD_DIR} make -j${NPROC}
    COMMAND ${CMAKE_COMMAND} -E chdir ${WOLFSSL_BUILD_DIR} make install
    COMMAND ${CMAKE_COMMAND} -E touch ${WOLFSSL_BUILD_DIR}/.built
    COMMENT "Building wolfSSL..."
    VERBATIM
)

add_custom_target(wolfssl DEPENDS ${WOLFSSL_BUILD_DIR}/.built)

# =============================================================================
# Step 2: Build libunwind
# =============================================================================
set(LIBUNWIND_DIR "${THIRDPARTY_DIR}/libunwind")
set(LIBUNWIND_BUILD_DIR "${BUILD_DIR}/libunwind_build")

add_custom_command(
    OUTPUT ${LIBUNWIND_BUILD_DIR}/.built
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LIBUNWIND_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIBUNWIND_DIR} autoreconf -i
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIBUNWIND_BUILD_DIR} ${LIBUNWIND_DIR}/configure
        --prefix=${INSTALL_PREFIX}
        --libdir=${LIB_DIR}
        --includedir=${INCLUDE_DIR}
        --enable-shared
        --disable-static
        --disable-tests
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIBUNWIND_BUILD_DIR} make -j${NPROC}
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIBUNWIND_BUILD_DIR} make install
    # Generate pkg-config file for libunwind
    COMMAND ${CMAKE_COMMAND} -E echo "prefix=${INSTALL_PREFIX}" > ${PKGCONFIG_DIR}/libunwind.pc
    COMMAND sh -c "echo 'libdir=${LIB_DIR}' >> ${PKGCONFIG_DIR}/libunwind.pc"
    COMMAND sh -c "echo 'includedir=${INCLUDE_DIR}' >> ${PKGCONFIG_DIR}/libunwind.pc"
    COMMAND ${CMAKE_COMMAND} -E echo "" >> ${PKGCONFIG_DIR}/libunwind.pc
    COMMAND ${CMAKE_COMMAND} -E echo "Name: libunwind" >> ${PKGCONFIG_DIR}/libunwind.pc
    COMMAND ${CMAKE_COMMAND} -E echo "Description: libunwind base library" >> ${PKGCONFIG_DIR}/libunwind.pc
    COMMAND ${CMAKE_COMMAND} -E echo "Version: 1.8.3" >> ${PKGCONFIG_DIR}/libunwind.pc
    COMMAND sh -c "echo 'Libs: -L\$${libdir} -lunwind' >> ${PKGCONFIG_DIR}/libunwind.pc"
    COMMAND sh -c "echo 'Cflags: -I\$${includedir}' >> ${PKGCONFIG_DIR}/libunwind.pc"
    COMMAND ${CMAKE_COMMAND} -E touch ${LIBUNWIND_BUILD_DIR}/.built
    DEPENDS wolfssl
    COMMENT "Building libunwind..."
    VERBATIM
)

add_custom_target(libunwind DEPENDS ${LIBUNWIND_BUILD_DIR}/.built)

# =============================================================================
# Step 3: Build bionic_translation
# =============================================================================
set(BIONIC_DIR "${THIRDPARTY_DIR}/bionic_translation")
set(BIONIC_BUILD_DIR "${BUILD_DIR}/bionic_build")

add_custom_command(
    OUTPUT ${BIONIC_BUILD_DIR}/.built
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BIONIC_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E env
        PKG_CONFIG_PATH=${PKGCONFIG_DIR}:$ENV{PKG_CONFIG_PATH}
        LD_LIBRARY_PATH=${LIB_DIR}:$ENV{LD_LIBRARY_PATH}
        C_INCLUDE_PATH=${INCLUDE_DIR}:$ENV{C_INCLUDE_PATH}
        CPLUS_INCLUDE_PATH=${INCLUDE_DIR}:$ENV{CPLUS_INCLUDE_PATH}
        LIBRARY_PATH=${LIB_DIR}:$ENV{LIBRARY_PATH}
        meson setup ${BIONIC_BUILD_DIR} ${BIONIC_DIR}
            --prefix=${INSTALL_PREFIX}
            --libdir=lib
            --buildtype=release
            -Dpkg_config_path=${PKGCONFIG_DIR}
    COMMAND ${CMAKE_COMMAND} -E env
        PKG_CONFIG_PATH=${PKGCONFIG_DIR}:$ENV{PKG_CONFIG_PATH}
        LD_LIBRARY_PATH=${LIB_DIR}:$ENV{LD_LIBRARY_PATH}
        C_INCLUDE_PATH=${INCLUDE_DIR}:$ENV{C_INCLUDE_PATH}
        CPLUS_INCLUDE_PATH=${INCLUDE_DIR}:$ENV{CPLUS_INCLUDE_PATH}
        LIBRARY_PATH=${LIB_DIR}:$ENV{LIBRARY_PATH}
        meson compile -C ${BIONIC_BUILD_DIR} -j${NPROC}
    # Copy libraries directly from the build directory (only .so files, not .p directories)
    COMMAND ${CMAKE_COMMAND} -E copy ${BIONIC_BUILD_DIR}/libdl_bio.so.0.0.1 ${LIB_DIR}/
    COMMAND ${CMAKE_COMMAND} -E copy ${BIONIC_BUILD_DIR}/libc_bio.so.0 ${LIB_DIR}/
    COMMAND ${CMAKE_COMMAND} -E copy ${BIONIC_BUILD_DIR}/libpthread_bio.so.0 ${LIB_DIR}/
    COMMAND ${CMAKE_COMMAND} -E copy ${BIONIC_BUILD_DIR}/libstdc++_bio.so.0 ${LIB_DIR}/
    # Create symlinks
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIB_DIR} ${CMAKE_COMMAND} -E create_symlink libdl_bio.so.0.0.1 libdl_bio.so
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIB_DIR} ${CMAKE_COMMAND} -E create_symlink libc_bio.so.0 libc_bio.so
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIB_DIR} ${CMAKE_COMMAND} -E create_symlink libpthread_bio.so.0 libpthread_bio.so
    COMMAND ${CMAKE_COMMAND} -E chdir ${LIB_DIR} ${CMAKE_COMMAND} -E create_symlink libstdc++_bio.so.0 libstdc++_bio.so
    COMMAND ${CMAKE_COMMAND} -E touch ${BIONIC_BUILD_DIR}/.built
    DEPENDS libunwind
    COMMENT "Building bionic_translation..."
    VERBATIM
)

add_custom_target(bionic_translation DEPENDS ${BIONIC_BUILD_DIR}/.built)

# =============================================================================
# Step 4: Build art_standalone
# =============================================================================
set(ART_DIR "${THIRDPARTY_DIR}/art_standalone")

add_custom_command(
    OUTPUT ${BUILD_DIR}/art_standalone/.built
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_DIR}/art_standalone
    # Create external/wolfssl directory with headers from our build
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${ART_DIR}/external/wolfssl
    COMMAND ${CMAKE_COMMAND} -E make_directory ${ART_DIR}/external/wolfssl
    # Copy all wolfssl headers including the built options.h
    COMMAND sh -c "cp -r ${THIRDPARTY_DIR}/wolfssl/wolfssl ${ART_DIR}/external/wolfssl/"
    COMMAND ${CMAKE_COMMAND} -E copy ${INSTALL_PREFIX}/include/wolfssl/options.h ${ART_DIR}/external/wolfssl/wolfssl/
    # Build art_standalone with wolfssl library path
    COMMAND ${CMAKE_COMMAND} -E env
        LIBRARY_PATH=${LIB_DIR}:$ENV{LIBRARY_PATH}
        LD_LIBRARY_PATH=${LIB_DIR}:$ENV{LD_LIBRARY_PATH}
        ${CMAKE_COMMAND} -E chdir ${ART_DIR} make -j${NPROC} ____LIBDIR=lib
    COMMAND ${CMAKE_COMMAND} -E chdir ${ART_DIR} make install
        ____PREFIX=${INSTALL_PREFIX}
        ____LIBDIR=lib
    # Copy binaries
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${ART_DIR}/out/host/linux-x86/bin/dx ${BIN_DIR}/
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${ART_DIR}/out/host/linux-x86/bin/dex2oat ${BIN_DIR}/
    COMMAND sh -c "test -f ${ART_DIR}/out/host/linux-x86/bin/dalvikvm64 && cp ${ART_DIR}/out/host/linux-x86/bin/dalvikvm64 ${BIN_DIR}/ || true"
    COMMAND sh -c "test -f ${ART_DIR}/out/host/linux-x86/bin/dalvikvm && cp ${ART_DIR}/out/host/linux-x86/bin/dalvikvm ${BIN_DIR}/ || true"
    # Copy art libraries
    COMMAND sh -c "cp -P ${ART_DIR}/out/host/linux-x86/lib64/*.so ${LIB_DIR}/art/ 2>/dev/null || true"
    # Copy JNI libraries
    COMMAND sh -c "cp -P ${ART_DIR}/out/host/linux-x86/lib64/libjavacore.so ${LIB_DIR}/java/dex/art/natives/ 2>/dev/null || true"
    COMMAND sh -c "cp -P ${ART_DIR}/out/host/linux-x86/lib64/libnativehelper.so ${LIB_DIR}/java/dex/art/natives/ 2>/dev/null || true"
    COMMAND sh -c "cp -P ${ART_DIR}/out/host/linux-x86/lib64/libopenjdk.so ${LIB_DIR}/java/dex/art/natives/ 2>/dev/null || true"
    COMMAND sh -c "cp -P ${ART_DIR}/out/host/linux-x86/lib64/libopenjdkjvm.so ${LIB_DIR}/java/dex/art/natives/ 2>/dev/null || true"
    COMMAND sh -c "cp -P ${ART_DIR}/out/host/linux-x86/lib64/libwolfssljni.so ${LIB_DIR}/java/dex/art/natives/ 2>/dev/null || true"
    # Copy jar files
    COMMAND sh -c "cp ${ART_DIR}/out/host/linux-x86/framework/*.jar ${LIB_DIR}/java/dex/art/ 2>/dev/null || true"
    COMMAND sh -c "cp ${ART_DIR}/out/host/common/obj/JAVA_LIBRARIES/core-all-hostdex_intermediates/classes.jar ${LIB_DIR}/java/core-all_classes.jar 2>/dev/null || true"
    COMMAND sh -c "cp ${ART_DIR}/out/host/common/obj/JAVA_LIBRARIES/core-junit-hostdex_intermediates/classes.jar ${LIB_DIR}/java/core-junit_classes.jar 2>/dev/null || true"
    COMMAND sh -c "cp ${ART_DIR}/out/host/common/obj/JAVA_LIBRARIES/junit-runner-hostdex_intermediates/classes.jar ${LIB_DIR}/java/junit-runner_classes.jar 2>/dev/null || true"
    # Copy dx.jar
    COMMAND sh -c "cp ${ART_DIR}/out/host/linux-x86/framework/dx.jar ${LIB_DIR}/java/ 2>/dev/null || true"
    # Copy headers
    COMMAND ${CMAKE_COMMAND} -E make_directory ${INCLUDE_DIR}/androidfw
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${ART_DIR}/libandroidfw/include/androidfw/androidfw_c_api.h
        ${INCLUDE_DIR}/androidfw/
    # Generate pkg-config file from template
    COMMAND sed "s|@PREFIX@|${BUILD_DIR}|g" ${CMAKE_SOURCE_DIR}/cmake/art-standalone.pc.in > ${PKGCONFIG_DIR}/art-standalone.pc
    COMMAND ${CMAKE_COMMAND} -E touch ${BUILD_DIR}/art_standalone/.built
    DEPENDS bionic_translation
    COMMENT "Building art_standalone..."
    VERBATIM
)

add_custom_target(art_standalone DEPENDS ${BUILD_DIR}/art_standalone/.built)

# =============================================================================
# Step 5: Build android_translation_layer with meson
# =============================================================================
set(ATL_BUILD_DIR "${BUILD_DIR}/atl_build")

add_custom_command(
    OUTPUT ${ATL_BUILD_DIR}/.built
    COMMAND ${CMAKE_COMMAND} -E make_directory ${ATL_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E env
        JAVA_HOME=${JAVA_HOME}
        PKG_CONFIG_PATH=${PKGCONFIG_DIR}:$ENV{PKG_CONFIG_PATH}
        LIBRARY_PATH=${LIB_DIR}:${LIB_DIR}/art:${BIONIC_BUILD_DIR}:$ENV{LIBRARY_PATH}
        LD_LIBRARY_PATH=${LIB_DIR}:${LIB_DIR}/art:$ENV{LD_LIBRARY_PATH}
        C_INCLUDE_PATH=${INCLUDE_DIR}:$ENV{C_INCLUDE_PATH}
        PATH=${BIN_DIR}:${JAVA_HOME}/bin:$ENV{PATH}
        meson setup ${ATL_BUILD_DIR} ${CMAKE_SOURCE_DIR}
            --prefix=${INSTALL_PREFIX}
            --libdir=lib
            --buildtype=release
            --wipe
            -Dpkg_config_path=${PKGCONFIG_DIR}
    COMMAND ${CMAKE_COMMAND} -E env
        JAVA_HOME=${JAVA_HOME}
        PKG_CONFIG_PATH=${PKGCONFIG_DIR}:$ENV{PKG_CONFIG_PATH}
        LIBRARY_PATH=${LIB_DIR}:${LIB_DIR}/art:${BIONIC_BUILD_DIR}:$ENV{LIBRARY_PATH}
        LD_LIBRARY_PATH=${LIB_DIR}:${LIB_DIR}/art:$ENV{LD_LIBRARY_PATH}
        C_INCLUDE_PATH=${INCLUDE_DIR}:$ENV{C_INCLUDE_PATH}
        PATH=${BIN_DIR}:${JAVA_HOME}/bin:$ENV{PATH}
        meson compile -C ${ATL_BUILD_DIR} -j${NPROC}
    COMMAND ${CMAKE_COMMAND} -E touch ${ATL_BUILD_DIR}/.built
    DEPENDS art_standalone
    COMMENT "Building android_translation_layer..."
    VERBATIM
)

add_custom_target(android_translation_layer DEPENDS ${ATL_BUILD_DIR}/.built)

# =============================================================================
# Default target
# =============================================================================
add_custom_target(all_build ALL DEPENDS android_translation_layer)

# =============================================================================
# Install target
# =============================================================================
add_custom_target(install_all
    COMMAND ${CMAKE_COMMAND} -E env
        PKG_CONFIG_PATH=${PKGCONFIG_DIR}:$ENV{PKG_CONFIG_PATH}
        LD_LIBRARY_PATH=${LIB_DIR}:${LIB_DIR}/art:$ENV{LD_LIBRARY_PATH}
        PATH=${BIN_DIR}:$ENV{PATH}
        meson install -C ${ATL_BUILD_DIR}
    DEPENDS android_translation_layer
    COMMENT "Installing android_translation_layer..."
)

# =============================================================================
# Clean target
# =============================================================================
add_custom_target(clean_all
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${WOLFSSL_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BIONIC_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUILD_DIR}/art_standalone
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${ATL_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E chdir ${ART_DIR} make clean || true
    COMMENT "Cleaning all build directories..."
)

# =============================================================================
# AppImage target
# =============================================================================
if(NOT WIN32)
    # Capture git version for the AppImage
    set(ATL_VERSION "")
    find_package(Git QUIET)
    if(Git_FOUND)
        execute_process(
            COMMAND ${GIT_EXECUTABLE} describe --tags --always --dirty
            WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
            OUTPUT_VARIABLE ATL_VERSION
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
    endif()

    add_custom_target(appimage
        COMMAND ${CMAKE_COMMAND} -E env
            ATL_BUILD_DIR="${CMAKE_BINARY_DIR}"
            ATL_VERSION="${ATL_VERSION}"
            bash "${CMAKE_SOURCE_DIR}/appimage/build-appimage.sh"
        DEPENDS all_build
        COMMENT "Building AppImage portable application..."
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        USAGE "cmake --build build --target appimage"
    )
endif()

message(STATUS "")
message(STATUS "=== Unified Build System Configuration ===")
message(STATUS "To build everything: cmake --build build")
message(STATUS "To install: cmake --build build --target install_all")
message(STATUS "To clean: cmake --build build --target clean_all")
message(STATUS "To build AppImage: cmake --build build --target appimage")
message(STATUS "")
