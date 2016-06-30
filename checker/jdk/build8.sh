#!/bin/sh

# Builds JDK 8 jar for Checker Framework by compiling annotated JDK
# source, extracting annotations, and inserting extracted annotations
# into ${JAVA_HOME}/lib/ct.sym.

# Optionally pass package directories as cmdline arguments (relative to
# $AJDK/src/share/classes)

# ensure CHECKERFRAMEWORK set
[ ! -z "$CHECKERFRAMEWORK" ] || export CHECKERFRAMEWORK=`(cd "$0/../.." && pwd)`

# Debugging
PRESERVE=1  # option to preserve intermediate files

# parameters derived from environment
# TOOLSJAR and CTSYM derived from JAVA_HOME, rest from CHECKERFRAMEWORK
JSR308="`cd $CHECKERFRAMEWORK/.. && pwd`"   # base directory
WORKDIR="${CHECKERFRAMEWORK}/checker/jdk"   # working directory
AJDK="${JSR308}/annotated-jdk8u-jdk"        # annotated JDK
SRCDIR="${AJDK}/src/share/classes"
BINDIR="${WORKDIR}/build"
BOOTDIR="${WORKDIR}/bootstrap"              # initial build w/o processors
TOOLSJAR="${JAVA_HOME}/lib/tools.jar"
LT_BIN="${JSR308}/jsr308-langtools/build/classes"
LT_JAVAC="${JSR308}/jsr308-langtools/dist/bin/javac"
CF_BIN="${CHECKERFRAMEWORK}/checker/build"
CF_DIST="${CHECKERFRAMEWORK}/checker/dist"
CF_JAR="${CF_DIST}/checker.jar"
CF_JAVAC="java -Xmx512m -jar ${CF_JAR} -Xbootclasspath/p:${BOOTDIR}"
CP="${BINDIR}:${BOOTDIR}:${LT_BIN}:${TOOLSJAR}:${CF_BIN}:${CF_JAR}"
JFLAGS="-XDignore.symbol.file=true -Xmaxerrs 20000 -Xmaxwarns 20000\
 -source 8 -target 8 -encoding ascii -cp ${CP}"
PROCESSORS="fenum,formatter,guieffect,i18n,i18nformatter,interning,linear,lock,nullness,signature,signedness,units"
PFLAGS="-Anocheckjdk -Aignorejdkastub -AuseDefaultsForUncheckedCode=bytecode,source -AprintErrorStack -Awarns"
JAIFDIR="${WORKDIR}/jaifs"
SYMDIR="${WORKDIR}/sym"

set -o pipefail
cd ${SRCDIR}

if [ $# -ne 0 ] ; then
DIRS=$*
mkdir -p ${BOOTDIR} ${BINDIR} ${WORKDIR}/log
else
rm -rf ${BOOTDIR} ${BINDIR} ${WORKDIR}/log
mkdir -p ${BOOTDIR} ${BINDIR} ${WORKDIR}/log

DIRS=`find com java javax jdk org sun \( -name META_INF -o -name dc\
 -o -name example -o -name jconsole -o -name pept -o -name snmp\
 -o -name internal -o -name security \) -prune -o -type d -print`
SI_DIRS=`find java javax jdk org com sun \( -name META_INF -o -name dc\
 -o -name example -o -name jconsole -o -name pept -o -name snmp \) -prune\
 -o -type d \( -name internal -o -name security \) -print`

if [ -z "${DIRS}" ] ; then
    echo "no annotated source files"
    exit 1
fi

# The bootstrap JDK, built from the same source as the final result but
# without any Checker Framework processors, obviates building the entire
# JDK source distribution.  You don't want to build the JDK from source.
echo "build bootstrap JDK"
find ${SI_DIRS} ${DIRS} -maxdepth 1 -name '*\.java' -print | xargs\
 ${LT_JAVAC} -g -d ${BOOTDIR} ${JFLAGS} -source 8 -target 8 -encoding ascii\
 -cp ${CP} | tee ${WORKDIR}/log/0.log
[ $? -ne 0 ] && exit 1
grep -q 'not found' ${WORKDIR}/log/0.log
(cd ${BOOTDIR} && jar cf ../jdk.jar *)

# These packages are interdependent and cannot be compiled individually.
# Compile them all together.
echo "build internal and security packages"
find ${SI_DIRS} -maxdepth 1 -name '*\.java' -print | xargs\
 ${CF_JAVAC} -g -d ${BINDIR} ${JFLAGS} -processor ${PROCESSORS} ${PFLAGS}\
 | tee ${WORKDIR}/log/1.log
[ $? -ne 0 ] && exit 1
fi

# Build the remaining packages one at a time because building all of
# them together makes the compiler run out of memory.
echo "build one package at a time w/processors on"
for d in ${DIRS} ; do
    ls $d/*.java 2>/dev/null || continue
    echo :$d: `echo $d/*.java | wc -w` files
    ${CF_JAVAC} -g -d ${BINDIR} ${JFLAGS} -processor ${PROCESSORS} ${PFLAGS}\
 "$d"/*.java 2>&1 | tee ${WORKDIR}/log/`echo "$d" | tr / .`.log
done

# Check logfiles for errors and list any source files that failed to
# compile.
grep -q -l 'Compilation unit: ' ${WORKDIR}/log/*
if [ $? -ne 0 ] ; then
    echo "failed" | tee ${WORKDIR}/log/2.log
    cat ${WORKDIR}/log/* | grep -l 'Compilation unit: ' | awk '{print$3}'\
 | sort -u | tee -a ${WORKDIR}/log/2.log
    exit 1
fi

# construct annotated ct.sym
bash ${WORKDIR}/annotate-ct-sym.sh |& tee ${WORKDIR}/log/2.log

cd ${WORKDIR}
cp jdk.jar ${CF_DIST}/jdk8.jar
[ ${PRESERVE} -eq 0 ] || rm -rf sym
