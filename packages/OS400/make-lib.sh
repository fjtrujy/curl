#!/usr/bin/env bash
#***************************************************************************
#                                  _   _ ____  _
#  Project                     ___| | | |  _ \| |
#                             / __| | | | |_) | |
#                            | (__| |_| |  _ <| |___
#                             \___|\___/|_| \_\_____|
#
# Copyright (C) Daniel Stenberg, <daniel@haxx.se>, et al.
#
# This software is licensed as described in the file COPYING, which
# you should have received as part of this distribution. The terms
# are also available at https://curl.se/docs/copyright.html.
#
# You may opt to use, copy, modify, merge, publish, distribute and/or sell
# copies of the Software, and permit persons to whom the Software is
# furnished to do so, under the terms of the COPYING file.
#
# This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
# KIND, either express or implied.
#
# SPDX-License-Identifier: curl
#
###########################################################################
#
#       libcurl compilation script for the OS/400.
#

SCRIPTDIR=$(dirname "${0}")
. "${SCRIPTDIR}/initscript.sh"
cd "${TOPDIR}/lib" || exit 1

#       Need to have IFS access to the mih/cipher header file.

if action_needed cipher.mih '/QSYS.LIB/QSYSINC.LIB/MIH.FILE/CIPHER.MBR'
then    rm -f cipher.mih
        ln -s '/QSYS.LIB/QSYSINC.LIB/MIH.FILE/CIPHER.MBR' cipher.mih
fi


#      Create and compile the identification source file.

{
        echo '#pragma comment(user, "libcurl version '"${LIBCURL_VERSION}"'")'
        echo '#pragma comment(user, __DATE__)'
        echo '#pragma comment(user, __TIME__)'
        echo '#pragma comment(copyright, "Copyright (C) Daniel Stenberg et al. OS/400 version by P. Monnerat")'
} > os400.c
make_module     OS400           os400.c         BUILDING_LIBCURL
LINK=                           # No need to rebuild service program yet.
MODULES=


#       Get source list (CSOURCES variable).

get_make_vars Makefile.inc


#       Compile the sources into modules.

# shellcheck disable=SC2034
INCLUDES="'$(pwd)'"

make_module     OS400SYS        "${SCRIPTDIR}/os400sys.c"       BUILDING_LIBCURL
make_module     CCSIDCURL       "${SCRIPTDIR}/ccsidcurl.c"      BUILDING_LIBCURL

for SRC in ${CSOURCES}
do      MODULE=$(db2_name "${SRC}")
        make_module "${MODULE}" "${SRC}" BUILDING_LIBCURL
done


#       If needed, (re)create the static binding directory.

if action_needed "${LIBIFSNAME}/${STATBNDDIR}.BNDDIR"
then    LINK=YES
fi

if [ -n "${LINK}" ]
then    rm -rf "${LIBIFSNAME}/${STATBNDDIR}.BNDDIR"
        CMD="CRTBNDDIR BNDDIR(${TARGETLIB}/${STATBNDDIR})"
        CMD="${CMD} TEXT('LibCurl API static binding directory')"
        CLcommand "${CMD}"

        for MODULE in ${MODULES}
        do      CMD="ADDBNDDIRE BNDDIR(${TARGETLIB}/${STATBNDDIR})"
                CMD="${CMD} OBJ((${TARGETLIB}/${MODULE} *MODULE))"
                CLcommand "${CMD}"
        done
fi


#       The exportation file for service program creation must be in a DB2
#               source file, so make sure it exists.

if action_needed "${LIBIFSNAME}/TOOLS.FILE"
then    CMD="CRTSRCPF FILE(${TARGETLIB}/TOOLS) RCDLEN(112)"
        CMD="${CMD} TEXT('curl: build tools')"
        CLcommand "${CMD}"
fi


#       Gather the list of symbols to export.
#       - Unfold lines from the header files so that they contain a semicolon.
#       - Keep only CURL_EXTERN definitions.
#       - Remove the CURL_DEPRECATED and CURL_TEMP_PRINTF macro calls.
#       - Drop the parenthesized function arguments and what follows.
#       - Keep the trailing function name only.

EXPORTS=$(cat "${TOPDIR}"/include/curl/*.h "${SCRIPTDIR}/ccsidcurl.h"   |
         sed -e 'H;s/.*//;x;s/\n//;s/.*/& /'                            \
             -e '/^CURL_EXTERN[[:space:]]/!d'                           \
             -e '/\;/!{x;d;}'                                           \
             -e 's/ CURL_DEPRECATED([^)]*)//g'                          \
             -e 's/ CURL_TEMP_PRINTF([^)]*)//g'                         \
             -e 's/[[:space:]]*(.*$//'                                  \
             -e 's/^.*[^A-Za-z0-9_]\([A-Za-z0-9_]*\)$/\1/')


#       Create the service program exportation file in DB2 member if needed.

BSF="${LIBIFSNAME}/TOOLS.FILE/BNDSRC.MBR"

if action_needed "${BSF}" Makefile.am
then    LINK=YES
fi

if [ -n "${LINK}" ]
then    echo " STRPGMEXP PGMLVL(*CURRENT) SIGNATURE('LIBCURL_${SONAME}')" \
            > "${BSF}"
        for EXPORT in ${EXPORTS}
        do      echo ' EXPORT    SYMBOL("'"${EXPORT}"'")' >> "${BSF}"
        done

        echo ' ENDPGMEXP' >> "${BSF}"
fi


#       Build the service program if needed.

if action_needed "${LIBIFSNAME}/${SRVPGM}.SRVPGM"
then    LINK=YES
fi

if [ -n "${LINK}" ]
then    CMD="CRTSRVPGM SRVPGM(${TARGETLIB}/${SRVPGM})"
        CMD="${CMD} SRCFILE(${TARGETLIB}/TOOLS) SRCMBR(BNDSRC)"
        CMD="${CMD} MODULE(${TARGETLIB}/OS400)"
        CMD="${CMD} BNDDIR(${TARGETLIB}/${STATBNDDIR}"
        if [ "${WITH_ZLIB}" != 0 ]
        then    CMD="${CMD} ${ZLIB_LIB}/${ZLIB_BNDDIR}"
                liblist -a "${ZLIB_LIB}"
        fi
        if [ "${WITH_LIBSSH2}" != 0 ]
        then    CMD="${CMD} ${LIBSSH2_LIB}/${LIBSSH2_BNDDIR}"
                liblist -a "${LIBSSH2_LIB}"
        fi
        CMD="${CMD})"
        CMD="${CMD} BNDSRVPGM(QADRTTS QGLDCLNT QGLDBRDR)"
        CMD="${CMD} TEXT('curl API library')"
        CMD="${CMD} TGTRLS(${TGTRLS})"
        CLcommand "${CMD}"
        LINK=YES
fi


#       If needed, (re)create the dynamic binding directory.

if action_needed "${LIBIFSNAME}/${DYNBNDDIR}.BNDDIR"
then    LINK=YES
fi

if [ -n "${LINK}" ]
then    rm -rf "${LIBIFSNAME}/${DYNBNDDIR}.BNDDIR"
        CMD="CRTBNDDIR BNDDIR(${TARGETLIB}/${DYNBNDDIR})"
        CMD="${CMD} TEXT('LibCurl API dynamic binding directory')"
        CLcommand "${CMD}"
        CMD="ADDBNDDIRE BNDDIR(${TARGETLIB}/${DYNBNDDIR})"
        CMD="${CMD} OBJ((*LIBL/${SRVPGM} *SRVPGM))"
        CLcommand "${CMD}"
fi
