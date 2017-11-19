#!/usr/bin/env bash

set -o errexit

# Parse arguments
configs=()
dirname="rootCA"
force=
verbose=0
usage() {
    echo "Usage: $0 [options]"
    echo " -h: This usage text"
    echo " -c: The config file to use to generate the root certificate. Can be repeated to"
    echo "     use multiple configs, which are merged in the order given, and options from"
    echo "     the later files will override options in the earlier files. If none are"
    echo "     specified, configs/ca.ini is used"
    echo " -d: The directory to store the root certificate & associated files in. The"
    echo "     default is 'rootCA'"
    echo " -f: Always generate new files, instead of reusing existing ones"
    echo " -v: Be more verbose. Can be repeated"
}
while getopts ":hc:d:fv" opt; do
    case "$opt" in
        h)
            usage
            exit 0
        ;;

        c)
            configs=("${configs[@]}" "$OPTARG")
        ;;

        d)
            dirname="$OPTARG"
        ;;

        f)
            force=1
        ;;

        v)
            verbose=$(($verbose + 1))
        ;;

        :)
            echo "Missing argument for option -$OPTARG" >&2
            usage >&2
            exit 1
        ;;

        *)
            echo "Illegal option -$OPTARG" >&2
            usage >&2
            exit 1
        ;;
    esac
done
shift $(($OPTIND - 1))
if [ -n "$1" ]; then
    echo "Extraneous arguments $@" >&2
    usage >&2
    exit 1
fi

# Helper method to print if verbosity is high enough
echov() {
    level="$1"
    shift
    if [ $verbose -ge $level ]; then
        echo "$@"
    fi
}

# Create & resolve the output path
echov 1 "> Creating & resolving output directory"
mkdir -p "$dirname"
outdir="$(cd "$dirname" && pwd)"

# If we're forcing recreating of all files, clear the output files
if [ $force ]; then
    rmifexists() {
        if [ -f "$1" ]; then
            echov 1 "> Removing existing file '$1'"
            rm "$1"
        fi
    }
    rmifexists "$outdir/config.ini"
    rmifexists "$outdir/index.txt"
    rmifexists "$outdir/index.txt.attr"
    rmifexists "$outdir/serial.txt"
    rmifexists "$outdir/rootCA.key"
    rmifexists "$outdir/rootCA.pem"
fi

# Create bookkeeping files
touch $outdir/index.txt $outdir/index.txt.attr
[ ! -f $outdir/serial.txt ] && echo '01' > $outdir/serial.txt

# Combine config files
if [ -f "$outdir/config" ]; then
    if [ ${#configs} -eq 0 ]; then
        echo "> Using existing config file '$outdir/config.ini', ignoring passed configs"
    else
        echo "> Using existing config file '$outdir/config.ini'"
    fi
else
    if [ ${#configs} -eq 0 ]; then
        configs=("$PWD/configs/ca.ini")
    fi
    echo "> Copying/merging config file(s) into '$outdir/config.ini'"
    cp "${configs[0]}" "$outdir/config.ini"
    for config in "${configs[@]}"; do
        echov 1 "> Applying config '$config'"
        crudini --merge "$outdir/config.ini" < "$config"
    done
fi

# Generate key
if [ -f "$outdir/rootCA.key" ]; then
    echo "> Using existing key '$outdir/rootCA.key'"
else
    echo "> Generating key"
    openssl genrsa \
        -des3 \
        -out "$outdir/rootCA.key" \
        2048
fi

# Generate certificate
if [ -f "$outdir/rootCA.pem" ]; then
    echo "> Using existing certificate '$outdir/rootCA.pem'"
else
    echo "> Generating certificate"
    openssl req \
        -new \
        -x509 \
        -config "$outdir/config.ini" \
        -key "$outdir/rootCA.key" \
        -out "$outdir/rootCA.pem"
fi

# Show info about the (generated) certificate
echo "> Info"
openssl x509 \
    -in "$outdir/rootCA.pem" \
    -noout \
    -text

# Show explanation on how to use, and considerations when doing so
echo "> Done"
echo "> You will have to import '$outdir/rootCA.pem' into your OS/browser"
echo "> Keep in mind that once you do this, any certificate signed by you will blindly be trusted"
echo "> Keep these files and passphrases secure!"

