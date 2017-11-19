#!/usr/bin/env bash

set -o errexit

# Parse arguments
configs=()
hosts=()
dirname="server"
cadirname="rootCA"
force=
verbose=0
usage() {
    echo "Usage: $0 [options]"
    echo " -h: This usage text"
    echo " -c: The config file to use to generate the certificate. Can be repeated to use"
    echo "     multiple configs, which are merged in the order given, and options from the"
    echo "     later files will override options in the earlier files. If none are"
    echo "     specified, configs/server.ini is used"
    echo " -d: The directory to store the certificate & associated files in. The default"
    echo "     is the primary host"
    echo " -a: The location of the certificate authority to use. The default is 'rootCA'"
    echo " -n: The host to generate an SSL certificate for (the common name). Can be"
    echo "     repeated to specify alternative names (SAN)"
    echo " -f: Always generate new files, instead of reusing existing ones"
    echo " -v: Be more verbose. Can be repeated"
}
while getopts ":hc:d:a:n:fv" opt; do
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

        a)
            cadirname="$OPTARG"
        ;;

        n)
            hosts=("${hosts[@]}" "$OPTARG")
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
if [ ${#hosts} -eq 0 ]; then
    echo "At least one host has to be specified" >&2
    usage >&2
    exit 1
fi
host="${hosts[0]}"

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

# Resolve the ca path
cadir="$(cd "$cadirname" && pwd)"

# If we're forcing recreating of all files, clear the output files
if [ $force ]; then
    rmifexists() {
        if [ -f "$1" ]; then
            echov 1 "> Removing existing file '$1'"
            rm "$1"
        fi
    }
    rmifexists "$outdir/config.ini"
    rmifexists "$outdir/request.csr"
    rmifexists "$outdir/ssl.key"
    rmifexists "$outdir/ssl.pem"
fi

# Combine config files
if [ -f "$outdir/config.ini" ]; then
    if [ ${#configs} -eq 0 ]; then
        echo "> Using existing config file '$outdir/config.ini', ignoring passed configs and hosts"
    else
        echo "> Using existing config file '$outdir/config.ini'"
    fi
else
    if [ ${#configs} -eq 0 ]; then
        configs=("$PWD/configs/server.ini")
    fi

    echo "> Copying/merging config file(s) into '$outdir/config.ini'"
    cp "${configs[0]}" "$outdir/config.ini"
    for config in "${configs[@]}"; do
        echov 1 "> Applying config '$config'"
        crudini --merge "$outdir/config.ini" < "$config"
    done

    crudinigetspecial() {
        crudini --get "$outdir/config.ini" "$1" "$2" 2> /dev/null ||\
        crudini --get "$outdir/config.ini" " $1 " "$2" ||\
        echo "$3"
    }

    echov 1 "> Reading section names from config"
    section_name="$(crudinigetspecial "req" "distinguished_name" "req_distinguished_name")"
    echov 2 "> Section for the distinguished name is '$section_name'"
    section_ext="$(crudinigetspecial "req" "req_extensions" "v3_req")"
    echov 2 "> Section for the extensions is '$section_ext'"
    section_san="$(crudinigetspecial "$section_ext" "subjectAltName" "v3_req")"
    section_san="${section_san/@}"
    echov 2 "> Section for the SAN is '$section_san'"

    echo "> Setting primary host in config"
    echov 1 "> Setting common name"
    crudini --set "$outdir/config.ini" "$section_name" "commonName_default" "$host"

    echo "> Setting all hosts as SAN in config"
    ip_index=1
    for i in "${!hosts[@]}"; do 
        h="${hosts[$i]}"
        crudini --set "$outdir/config.ini" "$section_san" "DNS.$i" "$h"
        echov 1 "> Set host '$h' as DNS.$i"
        if [ "$h" != "${h#*[0-9].[0-9]}" ] || [ "$h" != "${h#*:[0-9a-fA-F]}" ]; then
            crudini --set "$outdir/config.ini" "$section_san" "IP.$ip_index" "$h"
            echov 1 "> Set ip '$h' as IP.$ip_index"
            ip_index=$(($ip_index+1))
        fi
    done
fi

# Generate key
if [ -f "$outdir/ssl.key" ]; then
    echo "> Using existing key '$outdir/ssl.key'"
else
    echo "> Generating key"
    openssl genrsa -out "$outdir/ssl.key" 2048
fi

# Generating request
if [ -f "$outdir/request.csr" ]; then
    echo "> Using existing request '$outdir/request.csr'"
else

    echo "> Generating request"
    openssl req \
        -new \
        -nodes \
        -config "$outdir/config.ini" \
        -key "$outdir/ssl.key" \
        -out "$outdir/request.csr"
fi

echo "> Signing certificate"
(cd "$cadir" && openssl ca \
    -config "config.ini" \
    -policy signing_policy \
    -extensions signing_req \
    -out "$outdir/ssl.pem" \
    -infiles "$outdir/request.csr"
)

echo "> Info"
openssl x509 \
    -in "$outdir/ssl.pem" \
    -noout \
    -text

echo "> Done"

