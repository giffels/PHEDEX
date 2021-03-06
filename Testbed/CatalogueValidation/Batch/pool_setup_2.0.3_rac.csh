# set the catalogue contact strings
setenv MYSQL mysqlcatalog_mysql://phedex:phedex@cmslcgco04/phedexcat
setenv ORACLE relationalcatalog_oracle://itrac/radovan

# setup pool FC tools (POOL 2.0.3)
eval `cd /afs/cern.ch/sw/lcg/app/releases/POOL/POOL_2_0_3/src; scram -arch rh73_gcc32 runtime -csh`;

# setup Phedex Utilities
setenv PATH .:${PATH}:/afs/cern.ch/user/r/rehn/scratch0/PHEDEX/Utilities
setenv PYTHONPATH .:${PYTHONPATH}

# Oracle testsystem specific env variables
setenv POOL_AUTH_USER radovan
setenv POOL_AUTH_PASSWORD radovan
#setenv POOL_ORA_TS_TAB POOLDATA01
#setenv POOL_ORA_TS_IND POOLINDEX01
setenv TNS_ADMIN /afs/cern.ch/user/r/rado/public/oracle/ADMIN
setenv POOL_OUTMSG_LEVEL I
