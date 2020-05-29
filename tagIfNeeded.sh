#!/bin/bash

version_str="$(echo -e "$(<version)" | tr -d '[:space:]')"
IFS='.' read -ra zitiVer <<< "${version_str}"

zitiMajor=${zitiVer[0]}
zitiMinor=${zitiVer[1]}
zitiPatch=${zitiVer[2]}

echo "ZitiVersion: -${zitiMajor}-${zitiMinor}-${zitiPatch}-"

longVer=`git describe --long`
if [ $? -ne 0 ] ; then
   echo "No tag found. Adding ${version_str} based on 'version' file"
   git tag -a ${version_str} -m "CI tag ${version_str}"
   exit $?
fi

IFS='-' read -ra longVerArr <<< "${longVer}"
ahead=${longVerArr[1]}

IFS='.' read -ra tagVer <<< "${longVerArr[0]}"
tagMajor=${tagVer[0]}
tagMinor=${tagVer[1]}
tagPatch=${tagVer[2]}

echo "TagVersion: -${tagMajor}-${tagMinor}-${tagPatch}-"

[ ${zitiMajor} -gt ${tagMajor} ]
majorBump=$?

[ ${zitiMajor} -eq ${tagMajor} ] && [ ${zitiMinor} -gt ${tagMinor} ] 
minorBump=$?

[ ${zitiMajor} -eq ${tagMajor} ] && [ ${zitiMinor} -eq ${tagMinor} ] && [ ${zitiPatch} -gt ${tagPatch} ] 
patchBump=$?

if [ ${majorBump} -eq 0 ] || [ $minorBump -eq 0 ] || [ $patchBump -eq 0 ] ; then
   echo "Advancing tag based on 'version' file"
   git tag -a ${version_str} -m "CI tag ${version_str}"
else
   if [ ${ahead} -eq 0 ] ; then
      echo "Already has tag ${tagMajor}.${tagMinor}.${tagPatch}"
   else
      newTag="${tagMajor}.${tagMinor}.$((tagPatch + 1))"
      echo "Bumping up new tag to: ${newTag}"
      git tag -a ${newTag} -m "CI tag ${newTag}"
   fi   
fi
