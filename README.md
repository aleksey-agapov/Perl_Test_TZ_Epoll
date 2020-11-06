# Perl test job
Режим сжатия Zip включается параметром --crypt.


## Команда на запуск без сжатия
```
perl ./stubCry.pl 
```

## Команда на запуск c сжатием
```
perl ./stubCry.pl --crypt
```

## Тест на работу без сжатия
```
no_gzip_test.sh
```

## Тест на работу c сжатием
```
gzip_test.sh
```
