#!/bin/bash

# build_examples.sh
# This test script compiles each canonical* example in serial and parallel
# then executes the example program in 2D. The length of the test can be
# controlled by selecting default (1,000 steps), long (5,000 steps), or extra
# long (25,000 steps). The resulting checkpoints are then converted to PNG
# images to spot check problems in the code or environment, including execution
# errors and numerical instabilities. If you see something, say something.
#
# Questions/comments to trevor.keller@gmail.com (Trevor Keller)

# * Canonical examples exclude the following directories:
# differential_equations/elliptic/Poisson  --  segmentation faults
# beginners_diffusion  --  does not match execution pattern

# Valid flags are:
# --noexec: build in serial and parallel, but do not execute
# --noviz:  do not convert data for visualization
# --force:  pass -B flag to make
# -n X:     pass mpirun X ranks (e.g., -n 3 yields mpirun -np 3)
# --short:  execute tests .1x default
# --long:   execute tests  5x longer  than default
# --extra:  execute tests 25x longer  than default
# --clean:  delete binary files after test completes
# --purge:  delete binaries, data, and images after test completes

# Initialize timer and completion counters
tstart=$(date +%s)
SerERR=0
ParERR=0
RunERR=0
nSerBld=0
nParBld=0
nParRun=0
MFLAG="-s"

# Set execution parameters
ITERS=1000
INTER=500
CORES=4
COREMAX=$(nproc)

# Get going
cd ../examples
examples=$(pwd)

echo -n "Building examples in serial and parallel"


while [[ $# > 0 ]]
do
	key="$1"
	case $key in
		--force)
		echo -n ", forcing build"
		MFLAG="-Bs"
		;;
		--clean)
		echo -n ", cleaning up after"
		CLEAN=true
		;;
		--purge)
		echo -n ", cleaning up after"
		CLEAN=true
		PURGE=true
		;;
		--noexec)
		echo -n ", not executing"
		NEXEC=true
		;;
		--short)
		echo -n ", taking 100 steps"
		ITERS=100
		INTER=100
		;;
		--long)
		echo -n ", taking 5,000 steps"
		ITERS=5000
		INTER=1000
		;;
		--extra)
		echo -n ", taking 25,000 steps"
		ITERS=25000
		INTER=5000
		;;
		--noviz)
		echo -n ", not converting to PNG"
		NOVIZ=true
		;;
		-n)
		shift
		CORES=$1
		echo -n ", $CORES/$COREMAX MPI ranks"
		;;
		*)
		echo "WARNING: Unknown option ${key}."
		echo
    	;;
	esac
	shift # pop first entry from command-line argument list, reduce $# by 1
done

echo

if [[ ! $NOVIZ ]]
then
	# Remove existing images first. If the test fails,
	# no images in the directory is an obvious red flag.
	rm -f test.*.png
	if [[ $(which mmsp2png) == "" ]]
	then
		# Consult doc/MMSP.manual.pdf if this fails.
		echo "mmsp2png utility not found. Please check your installation,"
		echo " or pass --noviz flag to suppress PNG output."
	fi
fi

exdirs=("coarsening/grain_growth/anisotropic/Monte_Carlo/" \
"coarsening/grain_growth/anisotropic/phase_field/" \
"coarsening/grain_growth/anisotropic/sparsePF/" \
"coarsening/grain_growth/isotropic/Monte_Carlo/" \
"coarsening/grain_growth/isotropic/phase_field/" \
"coarsening/grain_growth/isotropic/sparsePF/" \
"coarsening/ostwald_ripening/isotropic/phase_field/" \
"coarsening/zener_pinning/anisotropic/Monte_Carlo/" \
"coarsening/zener_pinning/anisotropic/phase_field/" \
"coarsening/zener_pinning/anisotropic/sparsePF/" \
"coarsening/zener_pinning/isotropic/Monte_Carlo/" \
"coarsening/zener_pinning/isotropic/phase_field/" \
"coarsening/zener_pinning/isotropic/sparsePF/" \
"phase_transitions/allen-cahn/" \
"phase_transitions/cahn-hilliard/convex_splitting/" \
"phase_transitions/cahn-hilliard/explicit/" \
"phase_transitions/model_A/" \
"phase_transitions/model_B/" \
"phase_transitions/solidification/anisotropic/" \
"phase_transitions/spinodal/" \
"statistical_mechanics/Heisenberg/" \
"statistical_mechanics/Ising/" \
"statistical_mechanics/Potts/")

n=${#exdirs[@]}
for (( i=0; i<$n; i++ ))
do
	exstart=$(date +%s)
	j=$(($i+1))
	cd $examples/${exdirs[$i]}
	printf "%2d/%2d %-50s\t" $j $n ${exdirs[$i]}
	echo $(date) >test.log
	if make $MFLAG
	then
		((nSerBld++))
	else
		((SerERR++))
		tail test.log
	fi
	if make $MFLAG parallel
	then
		((nParBld++))
	else
		((ParERR++))
		tail test.log
	fi
	if [[ -f parallel ]] && [[ ! $NEXEC ]]
	then
		# Run the example in parallel, for speed.
		mpirun -np $CORES ./parallel --example 2 test.0000.dat >>test.log \
		&& mpirun -np $CORES ./parallel test.0000.dat $ITERS $INTER >>test.log
		# Return codes are tricky! Try testing bash $? variable
		if [[ $? ]]
		then
			((nParRun++))
		else
			((RunERR++))
			tail test.log
		fi
		if [[ ! $NOVIZ ]]
		then
			# Show the result
			for f in *.dat
			do
				mmsp2png --zoom $f >>test.log
			done
		fi
	fi
	# Clean up binaries and images
	if [[ $CLEAN ]]
	then
		make -s clean
		rm -f test.*.dat
		if [[ $PURGE ]]
		then
			rm -f test.*.png
			rm -f test.log
		fi
	fi

	exfin=$(date +%s)
	exlapse=$(echo "$exfin-$exstart" | bc -l)
	printf "%3d seconds\n" $exlapse
done

cd ${examples}

tfinish=$(date +%s)
elapsed=$(echo "$tfinish-$tstart" | bc -l)

printf "%67d seconds elapsed.\n" $elapsed
echo "${nSerBld} serial   examples built    successfully, ${SerERR} failed."
echo "${nParBld} parallel examples built    successfully, ${ParERR} failed."
echo "${nParRun} parallel examples executed successfully, ${RunERR} failed."
echo
cd ../test/

AllERR=$(echo "$SerERR+$ParERR+$RunERR" | bc -l)
if [[ $AllERR > 0 ]]
then
	echo "${AllERR} tests failed."
	echo
	exit 1
fi
