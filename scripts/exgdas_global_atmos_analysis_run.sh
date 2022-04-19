#!/bin/bash
################################################################################
####  UNIX Script Documentation Block
#                      .                                             .
# Script name:         exgdas_global_atmos_analysis_run.sh
# Script description:  Runs the global atmospheric analysis with FV3-JEDI
#
# Author: Cory Martin        Org: NCEP/EMC     Date: 2021-12-28
#
# Abstract: This script makes a global model atmospheric analysis using FV3-JEDI
#           and also (for now) updates increment files using a python ush utility
#
# $Id$
#
# Attributes:
#   Language: POSIX shell
#   Machine: Orion
#
################################################################################

#  Set environment.
export VERBOSE=${VERBOSE:-"YES"}
if [ $VERBOSE = "YES" ]; then
   echo $(date) EXECUTING $0 $* >&2
   set -x
fi

#  Directories
pwd=$(pwd)

#  Utilities
export NLN=${NLN:-"/bin/ln -sf"}
export INCPY=${INCPY:-"$HOMEgfs/sorc/gdas.cd/ush/jediinc2fv3.py"}
export GENYAML=${GENYAML:-"$HOMEgfs/sorc/gdas.cd/ush/genYAML"}
export GETOBSYAML=${GETOBSYAML:-"$HOMEgfs/sorc/gdas.cd/ush/get_obs_list.py"}

################################################################################
# make subdirectories
mkdir -p $DATA/fv3jedi
mkdir -p $DATA/obs
mkdir -p $DATA/diags
mkdir -p $DATA/bc
mkdir -p $DATA/anl

################################################################################
# generate YAML file
cat > $DATA/temp.yaml << EOF
template: ${ATMVARYAML}
output: $DATA/fv3jedi_var.yaml
config:
  atm: true
  BERROR_YAML: $BERROR_YAML
  OBS_DIR: obs
  DIAG_DIR: diags
  CRTM_COEFF_DIR: crtm
  BIAS_IN_DIR: obs
  BIAS_OUT_DIR: bc
  OBS_PREFIX: $OPREFIX
  BIAS_PREFIX: $GPREFIX
  OBS_LIST: $OBS_LIST
  OBS_YAML_DIR: $OBS_YAML_DIR
  BKG_DIR: bkg
  fv3jedi_staticb_dir: berror
  fv3jedi_fix_dir: fv3jedi
  fv3jedi_fieldset_dir: fv3jedi
  OBS_DATE: '$CDATE'
  BIAS_DATE: '$GDATE'
  ANL_DIR: anl/
EOF
$GENYAML --config $DATA/temp.yaml

################################################################################
# link observations to $DATA
$GETOBSYAML --config $DATA/fv3jedi_var.yaml --output $DATA/${OPREFIX}obsspace_list
files=$(cat $DATA/${OPREFIX}obsspace_list)
for file in $files; do
  basefile=$(basename $file)
  $NLN $COMOUT/$basefile $DATA/obs/$basefile
done

# link backgrounds to $DATA
# linking FMS RESTART files for now
# change to (or make optional) for cube sphere history later
$NLN ${COMIN_GES}/RESTART $DATA/bkg

################################################################################
# link fix files to $DATA
# static B
if [ $DOHYBVAR = "YES" ]; then
  CASE_BERROR=${CASE_BERROR:-${CASE_ENKF:-$CASE}}
else
  CASE_BERROR=${CASE_BERROR:-$CASE}
fi
$NLN $FV3JEDI_FIX/bump/$CASE_BERROR/ $DATA/berror

# vertical coordinate
LAYERS=$(expr $LEVS - 1)
$NLN $FV3JEDI_FIX/fv3jedi/fv3files/akbk${LAYERS}.nc4 $DATA/fv3jedi/akbk.nc4

# other FV3-JEDI fix files
$NLN $FV3JEDI_FIX/fv3jedi/fv3files/fmsmpp.nml $DATA/fv3jedi/fmsmpp.nml
$NLN $FV3JEDI_FIX/fv3jedi/fv3files/field_table_gfdl $DATA/fv3jedi/field_table

# fieldsets
fieldsets="dynamics.yaml ufo.yaml"
for fieldset in $fieldsets; do
  $NLN $FV3JEDI_FIX/fv3jedi/fieldsets/$fieldset $DATA/fv3jedi/$fieldset
done

# CRTM coeffs
$NLN $FV3JEDI_FIX/crtm/2.3.0_jedi $DATA/crtm

#  Link executable to $DATA
$NLN $JEDIVAREXE $DATA/fv3jedi_var.x

################################################################################
# run executable
export pgm=$JEDIVAREXE
. prep_step
$APRUN_ATMANAL $DATA/fv3jedi_var.x $DATA/fv3jedi_var.yaml 1>&1 2>&2
export err=$?; err_chk

################################################################################
# translate FV3-JEDI increment to FV3 readable format
atminc_jedi=`ls $DATA/anl/atminc_latlon*`
atminc_fv3=$COMOUT/${CDUMP}.${cycle}.atminc.nc
$INCPY $atminc_jedi $atminc_fv3

################################################################################
# Create log file noting creating of analysis increment file
echo "$CDUMP $CDATE atminc and tiled sfcanl done at `date`" > $COMOUT/${CDUMP}.${cycle}.loginc.txt

################################################################################
# Copy diags and YAML to $COMOUT
cp -r $DATA/fv3jedi_var.yaml $COMOUT/${CDUMP}.${cycle}.fv3jedi_var.yaml
cp -rf $DATA/diags $COMOUT/diags
cp -rf $DATA/bc $COMOUT/bc

################################################################################
set +x
if [ $VERBOSE = "YES" ]; then
   echo $(date) EXITING $0 with return code $err >&2
fi
exit $err

################################################################################
