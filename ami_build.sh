#!/bin/bash

zephyr_build_script_path="$(dirname $(readlink -f "$0"))"
zephyr_west_manifest_path="${zephyr_build_script_path}/ecfwwork"

function parameters_selection() {
    parameters=("chipset" "series" "soc")
    declare -A info

    function parameters_review() {
        local index=0
        tput clear
        echo "Information:"

        while [ ${index} -lt "${#parameters[@]}" ]; do
            local p="${parameters[${index}]}"
            echo "- ${p}:" "${info[${p}]}"
            index=$((index + 1))
        done
    }

    function parameter_setup() {
        local name="$1"; shift
        local selection=("$@")

        parameters_review
        echo -e "\nPlease select ${name}:"
        select s in "${selection[@]}" 'exit'; do
            case ${s} in
                'exit')
                    exit 0
                    ;;

                *)
                    for v in "${selection[@]}"; do
                        if [[ "${v}" == "${s}" ]]; then
                            info["${name}"]="${s}"
                            parameters_review
                            return 0
                        fi
                    done
                    ;;
            esac
        done
    }

    parameter_setup "chipset" "microchip"
    parameter_setup "series" "mec1501" "mec152x" "mec172x"
    parameter_setup "soc" "Alder Lake"
}

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
    # "mec_spi_gen_info" array contains below keys:
    # - "series": microchip series compatible with CPGZephyrDocs directory. ex. MEC1501, MEC152x, MEC172x
    # - "generator": spi generator file name. ex. everglades_spi_gen_lin64, everglades_spi_gen_RomE, mec172x_spi_gen_lin_x86_64
    # - "env": environment variable to set spi generator path. ex. EVERGLADES_SPI_GEN, MEC172X_SPI_GEN
    declare -A mec_spi_gen_info
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

    case "${zephyr_board}" in
        "mec150"*)
            mec_spi_gen_info["series"]="MEC1501"
            mec_spi_gen_info["generator"]="everglades_spi_gen_lin64"
            mec_spi_gen_info["env"]="EVERGLADES_SPI_GEN"

            if [[ $zephyr_board == *"modular_assy"* ]]; then
                set_zephyr_dconfig="-- -DCONFIG_MEC15XX_AIC_ON_TGL=y"
            fi
            ;;

        "mec152"*)
            mec_spi_gen_info["series"]="MEC152x"
            mec_spi_gen_info["generator"]="everglades_spi_gen_RomE"
            mec_spi_gen_info["env"]="EVERGLADES_SPI_GEN"
            # MEC152x compatible with MEC1501 in zephyr board
            set_zephyr_board="--board mec1501_adl"

            if [[ $zephyr_board == *"modular_assy"* ]]; then
                set_zephyr_dconfig="-- -DCONFIG_MEC15XX_AIC_ON_TGL=y"
            fi
            ;;

        "mec172"*)
            mec_spi_gen_info["series"]="MEC172x"
            mec_spi_gen_info["generator"]="mec172x_spi_gen_lin_x86_64"
            mec_spi_gen_info["env"]="MEC172X_SPI_GEN"

            if [[ $zephyr_board == *"modular_assy"* ]]; then
                set_zephyr_dconfig=" "
            fi
            ;;

        *)
            echo "${zephyr_board} is not supporting in ecfw project"
            exit 1
            ;;
    esac

    mec_spi_gen_chip_series_dir="${zephyr_mec_spi_gen_path}/${mec_spi_gen_info["series"]}"

    if [ ! -d "${mec_spi_gen_chip_series_dir}" ]; then
        echo "${mec_spi_gen_chip_series_dir} directory not found for ${zephyr_board}"
        exit 1
    fi

    mec_spi_gen="$(find ${mec_spi_gen_chip_series_dir} -name "${mec_spi_gen_info["generator"]}" -type f -print 2>/dev/null)"

    if [ -z "${mec_spi_gen_info["generator"]}" ]; then
        echo "spi generator not found for ${zephyr_board}"
        exit 1
    fi

    export "${mec_spi_gen_info["env"]}"="${mec_spi_gen}"
}

if [ "$#" -eq 0 ]; then
    parameters_selection
fi

check_and_setup_parameters
check_and_setup_west_topdir

if [[ "${zephyr_board}" =~ ^mec[[:digit:]]{2}.* ]]; then
    setup_microchip_config
fi

zephyr_app_path="${zephyr_west_topdir}/$(west config --local manifest.path)"
west build $set_zephyr_board -p=always -d build $set_zephyr_dconfig "${zephyr_app_path}"
