#!/bin/bash
# 2019'10, gokhan@kylone.com

#
# Evironment variables
#
#    RMVERBOSE  : increase verbosity (set any value)
#    RMISO      : official ISO to use (i.e. Rocky-8.3.2011-x86_64-boot.iso)
#    RMOUT      : resultig ISO file name (i.e. Rocky-8.3.2011-x86_64-minimal.iso)
#    RMETH      : dependency resolving method to use (deep or fast)
#
# Default values
#
# default official ISO to use
iso="Rocky-8.4-x86_64-minimal.iso"
#
# resulting ISO file name and volume label
# such values will be determined again according to source image during ISO mount
out="Rocky-8.4-x86_64-minimal-testing.iso"
lbl="Rocky-8-4-x86_64"
#
# dependency resolving method
# deep: check dependency of every package one by one
# fast: check core package depedencies only
met="fast"
#
# no need to change further

pw="$(pwd)"
dp="${pw}/image"
md="${pw}/mtemp"
bo="${dp}/BaseOS"

function rmusage() {
   echo "Usage: ${0} <run [force] | clean | debug [package [package ..]] | step ..>"
   echo
   exit 1
}

function rmusagestep() {
   echo "Usage: ${0} step .."
   echo
   echo " Workflow steps:"
   echo "    isomount"
   echo "    createtemplate"
   echo "    scandeps"
   echo "    createrepo"
   echo "    createiso"
   echo "    isounmount"
   echo
   echo " Some usefull functions:"
   echo "    rpmname <package> [package ..]"
   echo "    rpmurl <package> [package ..]"
   echo "    rpmdownload <package> [package ..]"
   echo "    fulldeps <package> [package ..]"
   echo
   exit 1
}

function rmnotrocky() {
   echo
   echo " ! This script is not suitable to use in this platform"
   echo
   exit 1
}

function rmcheck() {
  if [ "${PIPESTATUS[0]}" != "0" ]; then
    exit 1
  fi
}

function rmpipe() {
   while read line; do
      echo "   ${1}${line}"
   done
}

function rmdot() {
   if [ "${RMVERBOSE}" != "" ]; then
      rmpipe
   else
      echo -n "   "
      while read line; do
         echo -n "."
      done
      echo " done"
   fi
}

function rmisounmount() {
   if [ -d "${md}" ]; then
      echo -n " ~ unmount ISO .."
      umount "${md}" 2>/dev/null
      rmdir "${md}"
      echo " done"
   fi
}

function rmisomount() {
   if [ ! -e "${iso}" ]; then
      echo
      echo " ! Reference ISO (${iso}) not found."
      echo
      echo "   You can download Rocky 8 from following resource;"
      echo "   https://download.rockylinux.org/pub/rocky/8/isos/x86_64/"
      echo
      echo "   If you want to use different minor release, please"
      echo "   specify it like below;"
      echo
      echo "   RMISO='/path/to/file.iso' ./bootstrap.sh .."
      echo
      exit 1
   fi
   rmisounmount
   echo " ~ mount ISO "
   if [ ! -d "${md}" ]; then
      mkdir -p "${md}"
      mount -o loop "${iso}" "${md}" 2>&1 | rmpipe
      rmcheck
      echo "   ${md} mounted"
      if [ "$(cat "${md}/isolinux/isolinux.cfg" | grep "Rocky Linux 8")" == "" ]; then
         rmisounmount
         echo
         echo " ! Reference ISO should be one of the Rocky 8 distribution."
         echo
         exit
      fi
   fi
}

function rmclean() {
   rmisounmount
   rm -rf "${dp}"
   rm -f target_comps.xml "${out}" .[cpmrdtfu]*
}

function rmcreatetemplate() {
   if [ ! -d "${md}" ]; then
      if [ "${RMSTEP}" != "" ]; then
         echo " ! ISO not mounted, please run;"
         echo "   ${0} step isomount"
         echo
      fi
      return
   fi
   echo -n " ~ Preparing image template "
   echo -n "."
   mkdir -p "${dp}"
   mkdir -p "${bo}/Packages"
   echo -n "."
   cp -r "${md}/EFI" "${dp}/"
   rmcheck
   echo -n "."

   cp "templ_discinfo" "${dp}/.discinfo"
   cp "templ_media.repo" "${dp}/media.repo"
   echo -n "."
   cp -r "${md}/isolinux" "${dp}/"
   echo -n "."
   cp -r "${md}/images" "${dp}/"
   rmcheck
   rm -f "${dp}/.treeinfo"
   touch "${dp}/.treeinfo"
   while IFS=  read line; do
      imgf="$(echo "${line}" | grep "^images/" | awk -F" = " {'print $1'})"
      if [ "${imgf}" != "" ]; then
         if [ ! -e "${dp}/${imgf}" ]; then
            echo
            echo
            echo " ! Image '${imgf}' not found in base ISO"
            echo
            exit 1
         fi
         sum="$(sha256sum "${dp}/${imgf}" | awk {'print $1'})"
         echo "${imgf} = sha256:${sum}" >> "${dp}/.treeinfo"
         echo -n "."
      else
         echo "${line}" >> "${dp}/.treeinfo"
      fi
   done < "templ_treeinfo"
   if [ -e "${md}/.treeinfo" ]; then
      ts="$(cat ${md}/.treeinfo | grep "timestamp = " | head -1 | awk -F"= " {'print $2'} | tr -d "\n\r")"
      if [ "${ts}" != "" ]; then
         sed -i "s/\\(timestamp = \\)[0-9]\\+/\\1${ts}/g" "${dp}/.treeinfo"
      fi
   fi
   if [ -e "${md}/.discinfo" ]; then
      ts="$(head -1 ${md}/.discinfo | tr -d "\n\r")"
      if [ "${ts}" != "" ]; then
         sed -i "s/[0-9]\\+\.[0-9]\\+/${ts}/g" "${dp}/.discinfo"
      fi
   fi
   echo " done"
}

function resolvefast() {
   # input arguments
   # package [package ..]
   tf="${RMTEMP}"
   vb="${RMVERBOSE}"
   if [ "${vb}" != "" ]; then
      echo "${@}" | tr " " "\n" | rmpipe "   "
   fi
   repoquery --requires --resolve --recursive "${@}" 2>/dev/null | \
      awk -F":" {'print $1'} | \
      sed 's/\-[0-9]\+$//g' | \
      sort | uniq | \
      grep -v "glibc-all-langpacks\|glibc-langpack-[a-z0-9]\+$" \
   >> "${tf}"
}

function resolvedeep() {
   # input arguments
   # package [package ..]
   s="${RMSEP}-"
   tf="${RMTEMP}"
   vb="${RMVERBOSE}"
   repoquery --requires --resolve "${@}" 2>/dev/null | \
      awk -F":" {'print $1'} | \
      sed 's/\-[0-9]\+$//g' | \
      sort | uniq | \
   while read line; do
      if [ "${line}" == "glibc-all-langpacks" -o "$(echo "${line}" | grep "glibc-langpack-[a-z0-9]\+$")" != "" ]; then
         if [ "${vb}" != "" ]; then
            echo "       skip: ${@}	${line}"
         fi
         continue
      fi
      if [ "$(cat "${tf}" | grep "^${line}$")" == "" ]; then
         echo "${s} ${line}" >> .tree
         echo "${line}" >> "${tf}"
         if [ "${vb}" != "" ]; then
            echo "    package: ${@}	${line}"
         else
            echo -n ","
         fi
         RMSEP="${s}" resolvedeep "${line}"
      fi
   done
}

function rmfulldeps() {
   # input arguments
   # package [package ..]
   if [ "${1}" == "" ]; then
      echo "Usage: ${0} step fulldeps <package> [package ..]"
      echo
      exit
   fi
   rm -f ".pkgs" ".tree"
   touch ".pkgs" ".tree"
   echo " ~ Resolving dependencies for ${@}"
   if [ "${met}" == "deep" ]; then
      RMVERBOSE=1 RMSEP=" " RMTEMP=".pkgs" resolvedeep "${@}"
   else
      rm -f .fast
      RMVERBOSE=1 RMTEMP=".fast" resolvefast "${@}"
      cat .fast | sort | uniq > .pkgs
      rm -f .fast
   fi
   echo " ~ Full dependency list of ${1}"
   cat .pkgs | sort | rmpipe "   "
}

function rmcreatelist() {
   echo -n " ~ Creating package list "
   rm -f .core
   echo -n "."
   cat templ_comps.xml | grep packagereq | awk -F">" {'print $2'} | awk -F"<" {'print $1'} > .core
   echo -n "."
   cat packages.txt | grep -v "^#" | grep -v "^$" >> .core
   echo " done"
   tp="$(cat .core | sort | uniq | wc -l)"
   echo " ~ Resolving dependencies for ${tp} package(s)"
   if [ "${RMVERBOSE}" == "" ]; then
      echo -n "   "
   fi
   rm -f .tree .pkgs
   touch .pkgs
   cat .core | sort | uniq | while read line; do
      if [ "${met}" == "deep" ]; then
         if [ "${RMVERBOSE}" != "" ]; then
            RMTEMP=".pkgs" RMSEP=" " resolvedeep "${line}"
         fi
      fi
      echo "${line}" >> .pkgs
      if [ "${RMVERBOSE}" == "" ]; then
         echo -n "."
      fi
   done
   if [ "${met}" == "deep" ]; then
      if [ "${RMVERBOSE}" == "" ]; then
         RMTEMP=".pkgs" RMSEP=" " resolvedeep $(cat .core | sort | uniq | tr "\n" " ")
      fi
   else
      RMTEMP=".pkgs" resolvefast $(cat .core | sort | uniq | tr "\n" " ")
   fi
   rm -f .core
   cat .pkgs | sort | uniq > .pkgf
   mv .pkgf .pkgs
   if [ "${RMVERBOSE}" == "" ]; then
      echo " done"
   fi
}

function rmrpmdownload() {
   # input arguments
   # package [package ..]
   if [ "${1}" == "" ]; then
      echo "Usage: ${0} rpmdownload <package>"
      echo
      exit 1
   fi
   mkdir -p rpms
   dnf download --urls "${@}" 2>/dev/null | \
      grep "^http" | \
      sort | uniq | \
   while read u; do
      if [ "${u}" != "" ]; then
         f=`echo "${u}" | awk -F"/" {'print $NF'}`
         if [ -e "rpms/${f}" ]; then
            if [ "$(file "rpms/${f}" | grep "RPM ")" != "" ]; then
               echo " - exists (rpms/${f})"
               continue
            fi
            rm -f "rpms/${f}"
         fi
         echo "   ${f} [${u}]"
         curl -s "${u}" -o "rpms/${f}"
         if [ "${?}" == "0" ]; then
            if [ "$(file "rpms/${f}" | grep "RPM ")" == "" ]; then
               rm -f "rpms/${f}"
               echo " ! failed"
            fi
         else
            rm -f "rpms/${f}"
            echo " ! failed"
         fi
      fi
   done
}

function rpmdownload() {
   # input arguments
   # package [package ..]
   if [ "${1}" == "" ]; then
      echo " ! Pacakge name required for rpmdownload"
      echo
      exit 1
   fi
   ul="${RMURL}"
   if [ "${ul}" == "" ]; then
      ul="$(dnf download --urls "${@}" 2>/dev/null | \
            grep "^http" | \
            sort | uniq)"
   fi
   mkdir -p rpms
   echo "${ul}" | while read u; do
      if [ "${u}" != "" ]; then
         f=`echo "${u}" | awk -F"/" {'print $NF'}`
         if [ -e "rpms/${f}" ]; then
            if [ "$(file "rpms/${f}" | grep "RPM ")" != "" ]; then
               echo "${f}"
               continue
            fi
            rm -f "rpms/${f}"
         fi
         if [ -e "cache/${f}" ]; then
            cp "cache/${f}" "rpms/"
            echo "${f}"
            continue
         fi
         curl -s "${u}" -o "rpms/${f}"
         if [ "${?}" == "0" ]; then
            if [ "$(file "rpms/${f}" | grep "RPM ")" != "" ]; then
               echo "${u}" >> .dlrpm
               echo "${f}"
            else
               rm -f "rpms/${f}"
               echo "${u} -> ${f}" > .dler
            fi
         else
            rm -f "rpms/${f}"
            echo "${u} -> ${f}" > .dler
         fi
      fi
   done
}

function rmrpmurl() {
   # input arguments
   # package [package ..]
   if [ "${RMSTEP}" != "" -a "${1}" == "" ]; then
      echo "Usage: ${0} step rpmurl <package> [package ..]"
      echo
      exit 1
   fi
   dnf download --urls "${@}" | \
      grep "^http" | \
      sort | uniq > "${pw}/.urls"
}

function rmrpmname() {
   # input arguments
   # package [package ..]
   if [ "${RMSTEP}" != "" -a "${1}" == "" ]; then
      echo "Usage: ${0} step rpmname <package> [package ..]"
      echo
      exit 1
   fi
   repoquery "${@}" 2>/dev/null | \
      sed 's/\-[0-9]\+:/\-/g' | \
      awk {'print $1".rpm"'} | \
      sort | uniq
}

function rmcollectrpm() {
   # input arguments
   # package [package ..]
   vb="${RMVERBOSE}"
   if [ "${RMSTEP}" != "" -a "${1}" == "" ]; then
      echo "Usage: ${0} step collectrpm <package> [package ..]"
      echo
      exit 1
   fi
   rmrpmurl "${@}"
   dl="$(cat "${pw}/.urls")"
   rr="$(echo "${dl}" | awk -F"/" {'print $NF'} | sort | uniq)"
   if [ "${rr}" != "" ]; then
      mkdir -p rpms
      echo "${rr}" | while read r; do
         if [ -e "rpms/${r}" ]; then
            if [ -d "${bo}/Packages" ]; then
               cp "rpms/${r}" "${bo}/Packages/"
            fi
            if [ "${vb}" != "" ]; then
               echo "     cached: ${r}"
            else
               echo -n "."
            fi
         else
            pk="$(echo "${r}" | awk -F".el8" {'print $1'} | sed 's/\-[0-9\.\-]\+$//g')"
            fu="$(echo "${dl}" | grep "/${r}$")"
            if [ "${fu}" == "" ]; then
               ir="$(echo "${r}" | sed 's/\.x86_64/\.i686/g')"
               fu="$(echo "${dl}" | grep "/${ir}$")"
            fi
            if [ "$(echo "${fu}" | wc -l)" != "1" ]; then
               fu=""
               rp="$(echo "${r}" | awk -F".rpm" {'print $1'})"
               pk="$(dnf info "${rp}" | grep "^Name" | awk -F": " {'print $2'} | sort | uniq)"
            fi
            if [ "${vb}" != "" ]; then
               echo "downloading: ${pk}, ${r}"
            fi
            dd="$(RMURL="${fu}" rpmdownload "${pk}")"
            if [ "${dd}" == "" ]; then
               echo "${pk}:${r}:<none>" >> .miss
               if [ "${vb}" != "" ]; then
                  echo "  not found: ${r} (${pk})"
               else
                  echo -n "!"
               fi
            else
               echo "${dd}" | while read d; do
                  if [ "${d}" != "${r}" ]; then
                     if [ -d "${bo}/Packages" ]; then
                        cp "rpms/${d}" "${bo}/Packages/"
                     fi
                     if [ "${vb}" != "" ]; then
                        echo " dowmloaded: ${r} -> ${d}, ${pk}"
                     else
                        echo -n ":"
                     fi
                  else
                     if [ -d "${bo}/Packages" ]; then
                        cp "rpms/${d}" "${bo}/Packages/"
                     fi
                     if [ "${vb}" == "" ]; then
                        echo -n ":"
                     fi
                  fi
               done
            fi
         fi
      done
   else
      echo "${@}" >> .rslv
      args="${@}"
      if [ "${args}" != "" ]; then
         echo " unresolved: ${args}"
      else
         echo -n "!"
      fi
   fi
}

function rmcollectrpms() {
   tp="$(cat .pkgs | sort | uniq | wc -l)"
   echo " ~ Searching RPMs for ${tp} package(s)"
   if [ "${RMVERBOSE}" == "" ]; then
      echo -n "   "
   fi
   rm -f .miss .rslv .dler
   mkdir -p rpms
   rmcollectrpm $(cat .pkgs | sort | uniq | tr "\n" " ")
   if [ "${RMVERBOSE}" == "" ]; then
      echo " done"
   fi
}

function rmcreaterepo() {
   if [ ! -d "${bo}/Packages" ]; then
      echo " ! Image temmplate is not ready, please run;"
      echo "   ${0} step createtemplate"
      echo "   ${0} step scandeps"
      echo
      exit 1
   fi
   tp="$(cat "${pw}/packages.txt" | grep -v "^#" | grep -v "^$" | wc -l)"
   echo -n " ~ Creating component list for ${tp} add-on package "
   uc="${pw}/target_comps.xml"
   rm -f "${uc}"
   touch "${uc}"
   while IFS=  read xl; do
      if [ "${xl}" == "" ]; then
         cat "${pw}/packages.txt" | grep -v "^#" | grep -v "^$" | while read line; do
            echo "      <packagereq type=\"default\">${line}</packagereq>" >> "${uc}"
            echo -n "."
         done
      else
         echo "${xl}" >> "${uc}"
      fi
   done < "${pw}/templ_comps.xml"
   echo " done"
   echo " ~ Creating repodata "
   cd "${bo}"
   rmcheck
   rm -rf repodata
   createrepo -g "${uc}" . 2>&1 | rmdot
   rmcheck
   cd "${pw}"
   rm -f "${uc}"
}

function rmcreateiso() {
   if [ ! -d "${bo}/repodata" ]; then
      echo " ! Repo is not ready, please run;"
      echo "   ${0} step createrepo"
      echo
      exit 1
   fi
   lbl="$(cat "${dp}/isolinux/isolinux.cfg" | grep "LABEL=" | awk -F"LABEL=" {'print $2'} | awk {'print $1'} | grep -v "^$" | head -1 | tr -d "\n\r")"
   if [ "${RMOUT}" == "" ]; then
      ver="$(cat "${dp}/isolinux/isolinux.cfg" | grep "LABEL=Rocky" | head -1 | awk -F"LABEL=Rocky-" {'print $2'} | awk -F"-x86_64" {'print $1'} | sed 's/\-/\./g')"
      if [ "${ver}" == "8.BaseOS" ]; then
         ver="8.0.1905"
      elif [ "${ver}" == "Stream.8" ]; then
         ver="8.0.20191219"
      fi
      out="Rocky-${ver}-x86_64-minimal.iso"
   fi
   echo " ~ Creating ISO image"
   cd "${dp}"
   chmod 664 isolinux/isolinux.bin
   rm -f "${pw}/${out}"
   mkisofs \
      -input-charset utf-8 \
      -o "${pw}/${out}" \
      -b isolinux/isolinux.bin \
      -c isolinux/boot.cat \
      -no-emul-boot \
      -V "${lbl}" \
      -boot-load-size 4 \
      -boot-info-table \
      -eltorito-alt-boot \
      -e images/efiboot.img \
      -no-emul-boot \
      -R -J -v -T . 2>&1 | rmdot
      rmcheck
   if [ -e "/usr/bin/isohybrid" ]; then
      echo " ~ ISO hybrid"
      isohybrid --uefi "${pw}/${out}" | rmdot
      rmcheck
   fi
   if [ -e "/usr/bin/implantisomd5" ]; then
      echo " ~ Implant ISO MD5"
      implantisomd5 --force --supported-iso "${pw}/${out}" | rmdot
      rmcheck
   fi
   cd "${pw}"
   isz="$(du -h "${out}" | awk {'print $1'})"
   echo " ~ ISO image ready: ${out} (${isz})"
}

function rmjobsingle() {
   # input arguments
   # package [package ..]
   rm -f .[cpmrdtf]*
   touch .pkgs .tree
   echo " ~ Creating package list for ${@} "
   if [ "${met}" == "deep" ]; then
      RMVERBOSE=1 RMTEMP=".pkgs" RMSEP=" " resolvedeep "${@}"
   else
      rm -f .fast
      RMVERBOSE=1 RMTEMP=".fast" resolvefast "${@}"
      cat .fast | sort | uniq > .pkgs
   fi
   echo " ~ Package with dependencies"
   cat .pkgs | rmpipe "   "
   if [ "${met}" == "deep" ]; then
      echo " ~ Dependency tree"
      cat .tree | rmpipe "   "
   fi
   echo " ~ Searching RPMs"
   RMVERBOSE=1 rmcollectrpm $(cat .pkgs | sort | uniq | tr "\n" " ")
}

function rmscandeps() {
   rmcreatelist
   rmcollectrpms
}

function rmjobfull() {
   rmclean
   rmisomount
   rmcreatetemplate
   rmscandeps
   rmcreaterepo
   rmcreateiso
   rmisounmount
}

function rmjobquick() {
   if [ "${RMISO}" != "" ]; then
      rmisomount
   fi
   rmcreatetemplate
   rmcreaterepo
   rmcreateiso
   rmisounmount
}

if [ ! -e /etc/rocky-release ]; then
   rmnotrocky
fi
if [ "$(cat /etc/rocky-release | grep "Rocky Linux release 8")" == "" ]; then
   rmnotrocky
fi
if [ ! -e "/usr/bin/repoquery" -o ! -e "/usr/bin/createrepo" -o ! -e "/usr/bin/yumdownloader" -o ! -e "/usr/bin/dnf" -o ! -e "/usr/bin/curl" -o ! -e "/usr/bin/mkisofs" ]; then
   echo
   echo " ! Some additional packages needs to be installed."
   echo "   Please run following command to have them all:"
   echo
   echo "   yum -y install dnf yum yum-utils createrepo syslinux genisoimage isomd5sum bzip2 curl file"
   echo
   exit 1
fi
if [ "${RMISO}" != "" ]; then
   iso="${RMISO}"
fi
if [ "${RMOUT}" != "" ]; then
   out="${RMOUT}"
fi
if [ "${RMETH}" != "" ]; then
   met="${RMETH}"
fi
if [ ! -e "packages.txt" ]; then
   touch "packages.txt"
fi

if [ "${1}" == "run" ]; then
   shift
   if [ "${1}" == "force" ]; then
      rmjobfull
   elif [ -d "${bo}/Packages" ]; then
      rmjobquick
   else
      rmjobfull
   fi
elif [ "${1}" == "clean" ]; then
   rmclean
elif [ "${1}" == "debug" ]; then
   shift
   if [ "${1}" == "" ]; then
      rmusage
   fi
   rmjobsingle "${@}"
elif [ "${1}" == "step" ]; then
   shift
   if [ "${1}" == "" ]; then
      rmusagestep
   fi
   cmd="cm${1}"
   shift
   RMVERBOSE=1 RMSTEP=1 ${cmd} "${@}"
else
   rmusage
fi
