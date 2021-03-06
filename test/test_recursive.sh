#!/bin/bash
set -e

## build
cargo build --release

BIG_POWER=24
POWER=20
CUR_DIR=$(cd $(dirname $0);pwd)
ZKIT="${CUR_DIR}/../target/release/zkit"
CIRCUIT="circuit"

WORKSPACE=/tmp/recursive
rm -rf $WORKSPACE && mkdir -p $WORKSPACE

SRS=${CUR_DIR}/../keys/setup_2^${POWER}.key
BIG_SRS=${CUR_DIR}/../keys/setup_2^${BIG_POWER}.key

if [ ! -f $SRS ]; then
   curl https://universal-setup.ams3.digitaloceanspaces.com/setup_2^${POWER}.key -o $SRS
fi

if [ ! -f $BIG_SRS ]; then
   curl https://universal-setup.ams3.digitaloceanspaces.com/setup_2^${BIG_POWER}.key -o $BIG_SRS
fi

echo "1. compile circuit"
${ZKIT} compile -i ${CIRCUIT}.circom --O2=full -o $WORKSPACE

echo "2. export verification key"
${ZKIT} export_verification_key -s ${SRS} -c $WORKSPACE/${CIRCUIT}.r1cs -v $WORKSPACE/vk.bin

echo "3. generate each proof"
for wtns in `ls $CUR_DIR/recursive/input`
do
    input=$CUR_DIR/recursive/input/$wtns
    node ${WORKSPACE}/${CIRCUIT}_js/generate_witness.js \
        ${WORKSPACE}/${CIRCUIT}_js/${CIRCUIT}.wasm \
        $input/input.json $input/witness.wtns
    ${ZKIT} prove -c $WORKSPACE/${CIRCUIT}.r1cs -w $input/witness.wtns -b $input/proof.bin -s ${SRS} -t rescue
done

echo "4. collect old proof list"
OLD_PROOF_LIST=$WORKSPACE/old_proof_list.txt
> $OLD_PROOF_LIST

i=0
for wtns in `ls $CUR_DIR/recursive/input`
do
    input=${CUR_DIR}/recursive/input/$wtns
    echo $input/proof.bin >> $OLD_PROOF_LIST
    i=$((i+1))
done

cat $OLD_PROOF_LIST

echo "5. export recursive vk"
${ZKIT} export_recursive_verification_key -c $i -i 3 -s ${BIG_SRS} -v $WORKSPACE/recursive_vk.bin

echo "6. generate recursive proof"
${ZKIT} recursive_prove -s ${BIG_SRS} -f $OLD_PROOF_LIST  -v $WORKSPACE/vk.bin -n $WORKSPACE/recursive_proof.bin  -j $WORKSPACE/recursive_proof.json

echo "7. verify"
${ZKIT} recursive_verify -p $WORKSPACE/recursive_proof.bin -v $WORKSPACE/recursive_vk.bin

echo "8. generate verifier"
${ZKIT} generate_recursive_verifier -v $WORKSPACE/vk.bin -n $WORKSPACE/recursive_vk.bin -i 3 -s $WORKSPACE/verifier.sol
