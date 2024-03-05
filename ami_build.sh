#!/bin/bash

zephyr_build_script_path="$(dirname $(readlink -f "$0"))"
zephyr_west_manifest_path="${zephyr_build_script_path}/ecfwwork"

function check_and_setup_parameters() {
    zephyr_board="$1"

    if [ -z "$zephyr_board" ]; then
        zephyr_board="mec1501_adl"
    fi

    if [ -z "$BOARD" ]; then
        set_zephyr_board="--board $zephyr_board"
    else
        set_zephyr_board=" "
        zephyr_board="$BOARD"
    fi

    if [ -z "$ZEPHYR_TOOLCHAIN_VARIANT" ]; then
        export ZEPHYR_TOOLCHAIN_VARIANT='zephyr'
    fi
}

function check_and_setup_west_topdir() {
    zephyr_west_topdir="$(west topdir 2>/dev/null)" || {
        cd ${zephyr_build_script_path} || {
            echo "failed to change directory to build script path to get west topdir"
            exit 1
        }
    }

    zephyr_west_topdir="$(west topdir 2>/dev/null)" || {
        echo "failed to get west topdir"
        exit 1
    }

    echo "changed directorty to west topdir : ${zephyr_west_topdir}"
}

function setup_microchip_config() {
    set_zephyr_dconfig=" "
    zephyr_mec_spi_gen_path="${zephyr_west_manifest_path}/CPGZephyrDocs"
    mec_cpgzephyrdocs_repo="https://github.com/MicrochipTech/CPGZephyrDocs.git"

    if [ ! -d "${zephyr_mec_spi_gen_path}" ]; then
        echo "CPGZephyrDocs directory not found in ${zephyr_mec_spi_gen_path}"
        git clone --depth 1 ${mec_cpgzephyrdocs_repo} "${zephyr_mec_spi_gen_path}" || {
            echo "failed to clone microchip spi generator into ${zephyr_mec_spi_gen_path}"
            exit 1
        }
    fi

    if [[ $zephyr_board == "mec150"* ]]; then
        export EVERGLADES_SPI_GEN="$zephyr_west_topdir/$zephyr_mec_spi_gen_path/MEC1501/SPI_image_gen/everglades_spi_gen_lin64"
        if [[ $zephyr_board == *"modular_assy"* ]]; then
            set_zephyr_dconfig="-- -DCONFIG_MEC15XX_AIC_ON_TGL=y"
        fi
    elif [[ $zephyr_board == "mec152"* ]]; then
        export EVERGLADES_SPI_GEN="$zephyr_west_topdir/$zephyr_mec_spi_gen_path/MEC152x/SPI_image_gen/everglades_spi_gen_RomE"
        set_zephyr_board="-b mec1501_adl"
        if [[ $zephyr_board == *"modular_assy"* ]]; then
            set_zephyr_dconfig="-- -DCONFIG_MEC15XX_AIC_ON_TGL=y"
        fi
    elif [[ $zephyr_board == "mec172"* ]]; then
        export MEC172X_SPI_GEN="$zephyr_west_topdir/$zephyr_mec_spi_gen_path/MEC172x/SPI_image_gen/mec172x_spi_gen_lin_x86_64"
        if [[ $zephyr_board == *"modular_assy"* ]]; then
            set_zephyr_dconfig=" "
        fi
    else
        echo "$zephyr_board is not supporting in ecfw project"
        exit 1
    fi
}

check_and_setup_parameters
check_and_setup_west_topdir
setup_microchip_config

if [ -z "$ZEPHYR_TOOLCHAIN_VARIANT" ]; then
    export ZEPHYR_TOOLCHAIN_VARIANT='zephyr'
fi
zephyr_app_path="${zephyr_west_topdir}/$(west config --local manifest.path)"
west build $set_zephyr_board -p=always -d build $set_zephyr_dconfig "${zephyr_app_path}"
