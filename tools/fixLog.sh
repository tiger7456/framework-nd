find . -name *.h -o -name *.pl -o -name *.cpp -o -name *.hpp |xargs perl -pi -e 's/(\s)DEBUG\(/\1LOG_DEBUG\(/'
find . -name *.h -o -name *.pl -o -name *.cpp -o -name *.hpp |xargs perl -pi -e 's/(\s)TRACE\(/\1LOG_TRACE\(/'
find . -name *.h -o -name *.pl -o -name *.cpp -o -name *.hpp |xargs perl -pi -e 's/(\s)ERROR\(/\1LOG_ERROR\(/'
find . -name *.h -o -name *.pl -o -name *.cpp -o -name *.hpp |xargs perl -pi -e 's/(\s)FATAL\(/\1LOG_FATAL\(/'
find . -name *.h -o -name *.pl -o -name *.cpp -o -name *.hpp |xargs perl -pi -e 's/(\s)INFO\(/\1LOG_INFO\(/'
find . -name *.h -o -name *.pl -o -name *.cpp -o -name *.hpp |xargs perl -pi -e 's/(\s)WARN\(/\1LOG_WARN\(/'
