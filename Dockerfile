#FROM registry.hub.docker.com/java:openjdk-8-jdk
FROM  java:7
MAINTAINER jonaswu

WORKDIR /usr/local
RUN echo "deb http://debian.datastax.com/community stable main"  >> /etc/apt/sources.list.d/cassandra.sources.list
RUN curl -L http://debian.datastax.com/debian/repo_key | apt-key add -
# add python default scala is too old: 2.9 but we need 2.10
RUN apt-get update && (yes | apt-get install python-software-properties)
RUN yes | apt-get install software-properties-common
RUN apt-get install python-software-properties
RUN apt-add-repository -y ppa:fkrull/deadsnakes
# RUN apt-get update
RUN apt-get -y install python2.7 python-support libjna-java

#add scala
RUN curl -L http://www.scala-lang.org/files/archive/scala-2.10.4.tgz | tar -zx ; ln -s scala-2.10.4 scala
RUN curl -s http://d3kbcqa49mib13.cloudfront.net/spark-1.1.0.tgz| tar -xz ; ln -s spark-1.1.0 spark 


# To fix: Error: Invalid or corrupt jarfile sbt/sbt-launch-0.13.5.jar
RUN wget http://repo.typesafe.com/typesafe/ivy-releases/org.scala-sbt/sbt-launch/0.13.5/sbt-launch.jar 
RUN cp sbt-launch.jar spark/sbt/sbt-launch-0.13.5.jar
RUN cd spark ; sbt/sbt assembly

# use cassandra 2.0.10, because spark doesn't support cassandra 2.1 yet
RUN wget http://debian.datastax.com/community/pool/cassandra_2.0.10_all.deb ; dpkg -i cassandra_2.0.10_all.deb

# install ez_setup and pycass for future python support
#RUN curl -s https://bootstrap.pypa.io/ez_setup.py | python
#RUN easy_install cassandra-driver


# install and build spark-cassandra connector
RUN curl -L -s https://github.com/datastax/spark-cassandra-connector/archive/v1.1.0-alpha2.tar.gz | tar -zx ; ln -s spark-cassandra-connector-1.1.0-alpha2/ spark-cassandra-connector
RUN wget http://repo.typesafe.com/typesafe/ivy-releases/org.scala-sbt/sbt-launch/0.13.1/sbt-launch.jar 
RUN cp sbt-launch.jar spark-cassandra-connector/sbt/sbt-launch-0.13.1.jar
RUN cd spark-cassandra-connector ; sbt/sbt assembly || true

# java-driver-2.1.1 didn't work, so I use 2.1.0
RUN curl -L http://downloads.datastax.com/java-driver/cassandra-java-driver-2.1.0.tar.gz | tar -zx ; ln -s cassandra-java-driver-2.1.0 cassandra-java-driver

# install sbt
RUN curl -L -s https://dl.bintray.com/sbt/native-packages/sbt/0.13.6/sbt-0.13.6.tgz | tar -zx 

# cassandra host defaults to the real ip so we change it to localhost 
# RUN echo spark.cassandra.connection.host 127.0.0.1 >> /usr/local/spark/conf/spark-defaults.conf
RUN echo spark.executor.extraClassPath /usr/local/spark-cassandra-connector-1.1.0-alpha2/spark-cassandra-connector-java/target/scala-2.10/spark-cassandra-connector-java-assembly-1.1.0-alpha2.jar >> /usr/local/spark/conf/spark-defaults.conf
RUN echo spark.driver.extraClassPath /usr/local/spark-cassandra-connector-1.1.0-alpha2/spark-cassandra-connector-java/target/scala-2.10/spark-cassandra-connector-java-assembly-1.1.0-alpha2.jar >> /usr/local/spark/conf/spark-defaults.conf

# cassandra service warns trying to set ulimits in a container, so disable ulimit commands
RUN perl -pi.bak -e 's/ulimit/#ulimit/g' /etc/init.d/cassandra 

# install test data
WORKDIR /root
COPY trigrams /root/trigrams
COPY setup.sql /root/setup.sql
COPY trigram /root/trigram
RUN echo 'HOSTNAME=`hostname`; spark-shell --master spark://$HOSTNAME:7077' >> /root/start_spark.sh
RUN mkdir -p /root/.ssh
RUN echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDfDlvPEWbxqxgT/16b6n9o9azo9A1TJ2kUcL0vIaI6yJd8U6ISm9irFlVJv+8qR9qLiYwE45wHDb5iMkixFEfgh7GWm+d4MryJb1U2L1jnIZWskduGzzai3zaJCiaOF7TrrfVdzKFaQajHfqyskK3hG8Q8T+lebZQr8QWn5i1JXPMgYYacXBiO03IE9Wd6FpMqRGjTCl2lfMEzlecQGxOyhOAWFxEwaGkv74Zw1Qm7hy/pg2fFQ8kZt5NpQ3haaO9KVi8DXf0K+SEAJ5Y4x7wpMzm+yUe275z5YUypFBaVzzF0Ng1LhiVixwgcRR3MupdGbZ0vu1aq1A9r9avMD7dl jonaswu@jonaswu-ubuntu' >> /root/.ssh/authorized_keys

# Deploy startup script
ADD start.sh /root/start

# Configure supervisord
ADD supervisord.conf /etc/supervisord.conf
RUN mkdir -p /var/log/supervisor

# start cassandra and load test db
# RUN service cassandra start; sleep 15; cqlsh < setup.sql 

# build a nice simple script to run spark-cassandra
RUN echo '#!/bin/bash' > spark-cass ; echo 'spark-shell --jars $(echo /usr/local/cassandra-java-driver/*.jar /usr/local/spark-cassandra-connector/spark-cassandra-connector/target/scala-2.10/*.jar /usr/local/spark-cassandra-connector/spark-cassandra-connector-java/target/scala-2.10/*.jar /usr/share/cassandra/apache-cassandra-thrift-*.jar /usr/share/cassandra/lib/libthrift-*.jar /usr/local/cassandra-java-driver/lib/*.jar | sed -e "s/ /,/g")' >> spark-cass ; chmod 755 spark-cass
RUN echo 'SPARKPATH=$(echo /usr/local/cassandra-java-driver/*.jar /usr/local/spark-cassandra-connector/spark-cassandra-connector/target/scala-2.10/*.jar /usr/local/spark-cassandra-connector/spark-cassandra-connector-java/target/scala-2.10/*.jar /usr/share/cassandra/apache-cassandra-thrift-*.jar /usr/share/cassandra/lib/libthrift-*.jar /usr/local/cassandra-java-driver/lib/*.jar | sed -e "s/ /:/g")' >> spark-cass-env.sh 

RUN yes | apt-get install wget tar openssh-server supervisor openssl net-tools vim sudo

# set root password
RUN echo 'root:cowbei' | chpasswd

# Configure SSH server
# Create OpsCenter account
RUN mkdir -p /var/run/sshd && chmod -rx /var/run/sshd && \
	sed -ri 's/PermitRootLogin without-password/PermitRootLogin yes/g' /etc/ssh/sshd_config && \
	sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config && \
	sed -ri 's/#UsePAM no/UsePAM no/g' /etc/ssh/sshd_config && \
	useradd -m -G users,root -p $(openssl passwd -1 "cowbei") goodfriend && \
	echo "%root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

EXPOSE 7199 7000 7001 9160 9042
EXPOSE 22 8012 61621
EXPOSE 8080
USER root
ENV PATH /usr/local/spark/bin:/usr/local/cassandra/bin:/usr/local/sbt/bin:/usr/local/scala/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN echo "export PATH=$PATH:/usr/local/spark/bin:/usr/local/cassandra/bin:/usr/local/sbt/bin:/usr/local/scala/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/spark/sbin" >> /etc/bash.bashrc
CMD /bin/bash
#CMD service cassandra start && /bin/bash
