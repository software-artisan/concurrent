#!/bin/bash
set -eo pipefail
$SET_X

# this script is executed with mlflow-parallels/server/aws/ as the current directory
[ ! -f "template.yaml" ] && { echo "Error: needs to run in the directory mlflow-parallels/server/aws where template.yaml is located (and where directory lambdas exists): change directory and try again"; exit 1; }

if [ -x "$CONDA_PREFIX/bin/activate" ]; then
    source $CONDA_PREFIX/bin/activate base
else    # if $CONDA_PREFIX/bin/activate does not exist (this doesn't exist outside the docker container used to do builds), then use approach used by .bashrc; copied from .bashrc
    __conda_setup="$('conda' 'shell.bash' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    fi;
    conda activate base
fi; 
conda env remove -y --name mlflow-parallels-dev
conda create -y --name mlflow-parallels-dev python=3.8
if [ -x "$CONDA_PREFIX/bin/activate" ]; then
    source $CONDA_PREFIX/bin/activate mlflow-parallels-dev
else    
    # if $CONDA_PREFIX/bin/activate does not exist (this doesn't exist outside the docker container used to do builds)
    conda activate mlflow-parallels-dev
fi;    
pip install setuptools==57.5.0
#pip install awscli
#pip install boto3
#pip install botocore
pip install certifi==2021.10.8
pip install sqlparse
pip install mlflow==2.0.1
pip install infinstor
pip install infinstor_mlflow_plugin
pip install python-jose
pip install adal
pip install casbin
pip install kubernetes
pip install google-api-python-client
pip install google-cloud-container
# lambda error: /lib64/libc.so.6: version `GLIBC_2.28' not found (required by /opt/python/cryptography/hazmat/bindings/_rust.abi3.so)
# https://github.com/pyca/cryptography/issues/6390
# https://stackoverflow.com/questions/69475140/lambda-function-failing-with-lib64-libc-so-6-version-glibc-2-18-not-found
pip install cryptography==3.4.8
pip install pipdeptree
/bin/rm -f requirements.txt
pip freeze > requirements.txt

rm -rf package
pip install --target package/python -r requirements.txt
cp requirements.txt package/python

echo "Before trimming: Current size of python lambda layer: $(du -s -m package | awk '{print $1}' ) MB"

# remove unneeded directories to save space in the lambda layer
# package/python/scipy/integrate : scipy mathematical integration solver
for dir in package/python/mlflow/server/js/ \
    package/python/numpy package/python/pandas \
    package/python/scipy/integrate \
    package/python/sklearn \
    package/python/llvmlite \
    package/python/numba \
    package/python/matplotlib \
    package/python/fontTools \
    package/python/numpy.libs \
    package/python/pyarrow ; do
    echo "Removing directory to reduce python lambda layer size: $dir"
    rm -rf $dir
done;


# from searching mlflow source code, only scipy.parse is used.  So other scipy packages can be removed (as long as scipy.parse doesn't depend on it)
# remove scipy.linalg and scipy.special since they are not related to scipy.sparse above
for dir in package/python/scipy/integrate/tests \
    package/python/importlib_resources/tests \
    package/python/greenlet/tests \
    package/python/boto3 \
    package/python/botocore \
    package/python/scipy/sparse/tests \
    package/python/scipy/io/arff/tests \
    package/python/scipy/ndimage/tests \
    package/python/scipy/interpolate/tests \
    package/python/scipy/io/matlab/tests \
    package/python/scipy/io/tests \
    package/python/scipy/signal/tests \
    package/python/scipy/fftpack/tests \
    package/python/scipy/optimize/tests \
    package/python/scipy/linalg/tests \
    package/python/dulwich/tests \
    package/python/scipy/special/tests \
    package/python/scipy/spatial/tests \
    package/python/scipy/stats/tests \
    package/python/scipy/linalg \
    package/python/scipy.libs \
    package/python/PIL \
    package/python/Pillow.libs \
    package/python/scipy/special ; do
    
    [ -d $dir ] && { echo "Removing directory to reduce python lambda layer size: $dir";  rm -rf $dir; }
done;

# remove all __pycache__ directories to reduce size
find package/python -type d -name __pycache__ -exec rm -r {} \+

layer_size_bytes=$(du -s --bytes package | awk '{print $1}' )
echo "After trimming: Current size of python lambda layer: $layer_size_bytes"

max_layer_size=262144000
if [ "$layer_size_bytes" -gt  "$max_layer_size" ]; then
    echo "Error: layer size $layer_size_bytes is greater than $max_layer_size.  Fix layer size and try again."
    exit 1
fi
exit 0
