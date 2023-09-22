proxy1=$1
proxy2=$2

if [ ! -z $proxy1 ]; then
    yarn config set httpProxy $proxy1
fi

if [ ! -z $proxy2 ]; then
    yarn config set httpsProxy $proxy2
fi