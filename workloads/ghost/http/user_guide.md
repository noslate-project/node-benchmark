This is the user guide to download Ghost workload from public repo, and build the http working mode. It also downloads the ab tools as the client, and install the necessary DB as required by ghost official website.

```

ARG BASIC_IMAGE="node:latest"
FROM ${BASIC_IMAGE}

ENV USERNAME="ghost"

ARG DEBIAN_FRONTEND="noninteractive"
ARG TZ="America/Los_Angeles"
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1

# Install required packages that are not included in ubuntu core image
RUN apt-get update && apt --fix-broken install -y && apt-get upgrade -y && apt-get install -y \
    mysql-server \
    wget \
    vim \
    sysstat \
    sudo \
    nginx \
    apache2-utils && \
    rm -rf /var/lib/apt/lists/*

# Create new Linux account
RUN useradd -rm -d /home/${USERNAME} -s /bin/bash -g root -G sudo -u 1001 ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

# Switch to ${USERNAME}
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Upload ghost.dump database
COPY common/ghost.dump /home/${USERNAME}

# Configure mariadb and install ghost database
RUN echo "soft nofile 65536\nhard nofile 65536" | sudo tee -a /etc/security/limits.conf
RUN echo "\n[mysqld]\nopen_files_limit = 65536\nmax_connections = 10240" | sudo tee -a /etc/mysql/my.cnf

COPY common/setup_db.sh /tmp/setup_db.sh
RUN sudo chmod 777 /tmp/setup_db.sh && /tmp/setup_db.sh

# Download node v12.22.1 which is needed to install ghost, but will be removed afterwards
RUN wget https://nodejs.org/download/release/v12.22.1/node-v12.22.1-linux-x64.tar.xz

# Untar node v12.22.1
RUN tar xf node-v12.22.1-linux-x64.tar.xz
ENV ORIGINAL_PATH="${PATH}"
ENV PATH="/home/${USERNAME}/node-v12.22.1-linux-x64/bin:${ORIGINAL_PATH}"

# Install ghost
WORKDIR /home/${USERNAME}
RUN mkdir ghost-cli
WORKDIR /home/${USERNAME}/ghost-cli
RUN npm install ghost-cli@1.19.0
WORKDIR /home/${USERNAME}
RUN mkdir Ghost
WORKDIR /home/${USERNAME}/Ghost
RUN /home/${USERNAME}/ghost-cli/node_modules/.bin/ghost install 4.40.0 local
RUN /home/${USERNAME}/ghost-cli/node_modules/.bin/ghost status
COPY --chown=${USERNAME}:root common/config.production.json /home/${USERNAME}/Ghost

WORKDIR /home/${USERNAME}

# Remove node v12.22.1
RUN rm -rf /home/${USERNAME}/node-v12.22.1-linux-x64
RUN rm /home/${USERNAME}/node-v12.22.1-linux-x64.tar.xz

# Copy in scripts to run the workload
RUN mkdir /home/${USERNAME}/ghost-benchmark-scripts
COPY --chown=${USERNAME}:root common/ghost-benchmark-scripts /home/${USERNAME}/ghost-benchmark-scripts
COPY --chown=${USERNAME}:root common/quickrun.sh /home/${USERNAME}/Ghost

COPY --chown=${USERNAME}:root common/entrypoint.sh /usr/local/bin/entrypoint.sh

#nginx
RUN mkdir /home/${USERNAME}/nginx
COPY --chown=${USERNAME}:root common/nginx.conf.http  /home/${USERNAME}/nginx/nginx.conf

WORKDIR /home/${USERNAME}

# Install perf tools
RUN sudo -E apt-get update && sudo -E apt-get install -y flex bison python2 linux-tools-`uname -r`
ARG perf_version="linux-6.2"

# Download and build linux tools, remaining perf-archive
RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/${perf_version}.tar.xz && \
    tar xf ${perf_version}.tar.xz && \
    cd ${perf_version}/tools/perf && make CC=gcc ARCH=x86_64 && \
    cp perf-archive /home/${USERNAME}/Ghost/perf-archive && \
    rm -rf ${perf_version} ${perf_version}.tar.xz

# Clone FlameGraph and breakdown.sh
ARG FlameGraph_URL="https://github.com/brendangregg/FlameGraph.git"
RUN git clone --depth 1 --branch master ${FlameGraph_URL}
COPY --chown=${USERNAME}:root common/breakdown.sh /home/${USERNAME}/Ghost/breakdown.sh
COPY --chown=${USERNAME}:root common/perf_module_breakdown.py /home/${USERNAME}/Ghost/perf_module_breakdown.py

WORKDIR /home/${USERNAME}/Ghost

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD [ "bash" ]

```

To make the workload workload, you need to fill in some data in the DB.
Ususally you need to import some dump data according to official website. Below is just a sample for you referece.
You need to save below dump content as file `ghost.dump` and put the file into `ghost/common` folder.

```
-- MySQL dump 10.16  Distrib 10.2.30-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: ghost
-- ------------------------------------------------------
-- Server version	10.2.30-MariaDB-1:10.2.30+maria~bionic

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

DROP DATABASE IF EXISTS ghost;

CREATE DATABASE ghost;

USE ghost;

--
-- Table structure for table `actions`
--

DROP TABLE IF EXISTS `actions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `actions` (
  `id` varchar(24) NOT NULL,
  `resource_id` varchar(24) DEFAULT NULL,
  `resource_type` varchar(50) NOT NULL,
  `actor_id` varchar(24) NOT NULL,
  `actor_type` varchar(50) NOT NULL,
  `event` varchar(50) NOT NULL,
  `context` text DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `actions`
--

LOCK TABLES `actions` WRITE;
/*!40000 ALTER TABLE `actions` DISABLE KEYS */;
INSERT INTO `actions` VALUES ('5e0b7269bd3aed420a989165','1','user','1','user','edited',NULL,'2019-12-31 16:08:09'),('5e0b727fbd3aed420a989166','5e0ae6529518860c8fd3fdad','post','1','user','deleted',NULL,'2019-12-31 16:08:31'),('5e0b7286bd3aed420a989167','5e0ae6529518860c8fd3fdab','post','1','user','deleted',NULL,'2019-12-31 16:08:38'),('5e0b7290bd3aed420a989168','5e0ae6529518860c8fd3fda9','post','1','user','deleted',NULL,'2019-12-31 16:08:48'),('5e0b7297bd3aed420a989169','5e0ae6529518860c8fd3fda7','post','1','user','deleted',NULL,'2019-12-31 16:08:55'),('5e0b729ebd3aed420a98916a','5e0ae6529518860c8fd3fda5','post','1','user','deleted',NULL,'2019-12-31 16:09:02'),('5e0b72a5bd3aed420a98916b','5e0ae6529518860c8fd3fda3','post','1','user','deleted',NULL,'2019-12-31 16:09:09'),('5e0b72acbd3aed420a98916c','5e0ae6529518860c8fd3fda1','post','1','user','deleted',NULL,'2019-12-31 16:09:16'),('5e0b72b3bd3aed420a989170','5e0b72b3bd3aed420a98916d','post','1','user','added',NULL,'2019-12-31 16:09:23'),('5e0b72bdbd3aed420a989172','5e0b72b3bd3aed420a98916d','post','1','user','edited',NULL,'2019-12-31 16:09:33'),('5e0b72bfbd3aed420a989173','5e0b72b3bd3aed420a98916d','post','1','user','edited',NULL,'2019-12-31 16:09:35'),('5e0b72d6bd3aed420a989175','5e0b72b3bd3aed420a98916d','post','1','user','edited',NULL,'2019-12-31 16:09:58'),('5e0b7307bd3aed420a989177','5e0b72b3bd3aed420a98916d','post','1','user','edited',NULL,'2019-12-31 16:10:47'),('5e0b730cbd3aed420a989178','5e0b72b3bd3aed420a98916d','post','1','user','edited',NULL,'2019-12-31 16:10:52');
/*!40000 ALTER TABLE `actions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `api_keys`
--

DROP TABLE IF EXISTS `api_keys`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `api_keys` (
  `id` varchar(24) NOT NULL,
  `type` varchar(50) NOT NULL,
  `secret` varchar(191) NOT NULL,
  `role_id` varchar(24) DEFAULT NULL,
  `integration_id` varchar(24) DEFAULT NULL,
  `last_seen_at` datetime DEFAULT NULL,
  `last_seen_version` varchar(50) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_keys_secret_unique` (`secret`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `api_keys`
--

LOCK TABLES `api_keys` WRITE;
/*!40000 ALTER TABLE `api_keys` DISABLE KEYS */;
INSERT INTO `api_keys` VALUES ('5e0ae6529518860c8fd3fdb0','admin','906d46ba3c3d5892dd4fd5909504ab6159d22b293388cc501d4acd218e8dcd8c','5e0ae63f9518860c8fd3fd5a','5e0ae6529518860c8fd3fdaf',NULL,NULL,'2019-12-31 06:10:26','1','2019-12-31 06:10:26','1'),('5e0ae6529518860c8fd3fdb2','admin','f05bdbbc1f9be0fe0a732d822c023032f0b228d6f3e52211b4f0395649f1f0ff','5e0ae63f9518860c8fd3fd5b','5e0ae6529518860c8fd3fdb1',NULL,NULL,'2019-12-31 06:10:26','1','2019-12-31 06:10:26','1'),('5e0ae6529518860c8fd3fdb4','admin','41b546a98d68b2303618e5ca94cfa660203f8fc2e445848df39452f335488df6','5e0ae63f9518860c8fd3fd5c','5e0ae6529518860c8fd3fdb3',NULL,NULL,'2019-12-31 06:10:26','1','2019-12-31 06:10:26','1');
/*!40000 ALTER TABLE `api_keys` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `app_fields`
--

DROP TABLE IF EXISTS `app_fields`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `app_fields` (
  `id` varchar(24) NOT NULL,
  `key` varchar(50) NOT NULL,
  `value` text DEFAULT NULL,
  `type` varchar(50) NOT NULL DEFAULT 'html',
  `app_id` varchar(24) NOT NULL,
  `relatable_id` varchar(24) NOT NULL,
  `relatable_type` varchar(50) NOT NULL DEFAULT 'posts',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `app_fields_app_id_foreign` (`app_id`),
  CONSTRAINT `app_fields_app_id_foreign` FOREIGN KEY (`app_id`) REFERENCES `apps` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_fields`
--

LOCK TABLES `app_fields` WRITE;
/*!40000 ALTER TABLE `app_fields` DISABLE KEYS */;
/*!40000 ALTER TABLE `app_fields` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `app_settings`
--

DROP TABLE IF EXISTS `app_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `app_settings` (
  `id` varchar(24) NOT NULL,
  `key` varchar(50) NOT NULL,
  `value` text DEFAULT NULL,
  `app_id` varchar(24) NOT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `app_settings_key_unique` (`key`),
  KEY `app_settings_app_id_foreign` (`app_id`),
  CONSTRAINT `app_settings_app_id_foreign` FOREIGN KEY (`app_id`) REFERENCES `apps` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_settings`
--

LOCK TABLES `app_settings` WRITE;
/*!40000 ALTER TABLE `app_settings` DISABLE KEYS */;
/*!40000 ALTER TABLE `app_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `apps`
--

DROP TABLE IF EXISTS `apps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `apps` (
  `id` varchar(24) NOT NULL,
  `name` varchar(191) NOT NULL,
  `slug` varchar(191) NOT NULL,
  `version` varchar(50) NOT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'inactive',
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `apps_name_unique` (`name`),
  UNIQUE KEY `apps_slug_unique` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `apps`
--

LOCK TABLES `apps` WRITE;
/*!40000 ALTER TABLE `apps` DISABLE KEYS */;
/*!40000 ALTER TABLE `apps` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `brute`
--

DROP TABLE IF EXISTS `brute`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `brute` (
  `key` varchar(191) NOT NULL,
  `firstRequest` bigint(20) NOT NULL,
  `lastRequest` bigint(20) NOT NULL,
  `lifetime` bigint(20) NOT NULL,
  `count` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `brute`
--

LOCK TABLES `brute` WRITE;
/*!40000 ALTER TABLE `brute` DISABLE KEYS */;
INSERT INTO `brute` VALUES ('oHUubZQTM66eOWJCFaoi+8dO/eXPG5zwBOW8P5YAuKM=',1577808442408,1577808442408,1577812042411,1);
/*!40000 ALTER TABLE `brute` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `emails`
--

DROP TABLE IF EXISTS `emails`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `emails` (
  `id` varchar(24) NOT NULL,
  `post_id` varchar(24) NOT NULL,
  `uuid` varchar(36) NOT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'pending',
  `error` varchar(2000) DEFAULT NULL,
  `error_data` longtext DEFAULT NULL,
  `meta` text DEFAULT NULL,
  `stats` text DEFAULT NULL,
  `email_count` int(10) unsigned NOT NULL DEFAULT 0,
  `subject` varchar(300) DEFAULT NULL,
  `html` longtext DEFAULT NULL,
  `plaintext` longtext DEFAULT NULL,
  `submitted_at` datetime NOT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `emails_post_id_unique` (`post_id`),
  KEY `emails_post_id_index` (`post_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `emails`
--

LOCK TABLES `emails` WRITE;
/*!40000 ALTER TABLE `emails` DISABLE KEYS */;
/*!40000 ALTER TABLE `emails` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `integrations`
--

DROP TABLE IF EXISTS `integrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `integrations` (
  `id` varchar(24) NOT NULL,
  `type` varchar(50) NOT NULL DEFAULT 'custom',
  `name` varchar(191) NOT NULL,
  `slug` varchar(191) NOT NULL,
  `icon_image` varchar(2000) DEFAULT NULL,
  `description` varchar(2000) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `integrations_slug_unique` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `integrations`
--

LOCK TABLES `integrations` WRITE;
/*!40000 ALTER TABLE `integrations` DISABLE KEYS */;
INSERT INTO `integrations` VALUES ('5e0ae6529518860c8fd3fdaf','builtin','Zapier','zapier',NULL,'Built-in Zapier integration','2019-12-31 06:10:26','1','2019-12-31 06:10:26','1'),('5e0ae6529518860c8fd3fdb1','internal','Ghost Backup','ghost-backup',NULL,'Internal DB Backup integration','2019-12-31 06:10:26','1','2019-12-31 06:10:26','1'),('5e0ae6529518860c8fd3fdb3','internal','Ghost Scheduler','ghost-scheduler',NULL,'Internal Scheduler integration','2019-12-31 06:10:26','1','2019-12-31 06:10:26','1');
/*!40000 ALTER TABLE `integrations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `invites`
--

DROP TABLE IF EXISTS `invites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `invites` (
  `id` varchar(24) NOT NULL,
  `role_id` varchar(24) NOT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'pending',
  `token` varchar(191) NOT NULL,
  `email` varchar(191) NOT NULL,
  `expires` bigint(20) NOT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `invites_token_unique` (`token`),
  UNIQUE KEY `invites_email_unique` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `invites`
--

LOCK TABLES `invites` WRITE;
/*!40000 ALTER TABLE `invites` DISABLE KEYS */;
/*!40000 ALTER TABLE `invites` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `members`
--

DROP TABLE IF EXISTS `members`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `members` (
  `id` varchar(24) NOT NULL,
  `uuid` varchar(36) DEFAULT NULL,
  `email` varchar(191) NOT NULL,
  `name` varchar(191) DEFAULT NULL,
  `note` varchar(2000) DEFAULT NULL,
  `subscribed` tinyint(1) DEFAULT 1,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `members_email_unique` (`email`),
  UNIQUE KEY `members_uuid_unique` (`uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `members`
--

LOCK TABLES `members` WRITE;
/*!40000 ALTER TABLE `members` DISABLE KEYS */;
/*!40000 ALTER TABLE `members` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `members_stripe_customers`
--

DROP TABLE IF EXISTS `members_stripe_customers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `members_stripe_customers` (
  `id` varchar(24) NOT NULL,
  `member_id` varchar(24) NOT NULL,
  `customer_id` varchar(255) NOT NULL,
  `name` varchar(191) DEFAULT NULL,
  `email` varchar(191) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `members_stripe_customers`
--

LOCK TABLES `members_stripe_customers` WRITE;
/*!40000 ALTER TABLE `members_stripe_customers` DISABLE KEYS */;
/*!40000 ALTER TABLE `members_stripe_customers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `members_stripe_customers_subscriptions`
--

DROP TABLE IF EXISTS `members_stripe_customers_subscriptions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `members_stripe_customers_subscriptions` (
  `id` varchar(24) NOT NULL,
  `customer_id` varchar(255) NOT NULL,
  `subscription_id` varchar(255) NOT NULL,
  `plan_id` varchar(255) NOT NULL,
  `status` varchar(50) NOT NULL,
  `cancel_at_period_end` tinyint(1) NOT NULL DEFAULT 0,
  `current_period_end` datetime NOT NULL,
  `start_date` datetime NOT NULL,
  `default_payment_card_last4` varchar(4) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  `plan_nickname` varchar(50) NOT NULL,
  `plan_interval` varchar(50) NOT NULL,
  `plan_amount` int(11) NOT NULL,
  `plan_currency` varchar(191) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `members_stripe_customers_subscriptions`
--

LOCK TABLES `members_stripe_customers_subscriptions` WRITE;
/*!40000 ALTER TABLE `members_stripe_customers_subscriptions` DISABLE KEYS */;
/*!40000 ALTER TABLE `members_stripe_customers_subscriptions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `migrations`
--

DROP TABLE IF EXISTS `migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `migrations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(120) NOT NULL,
  `version` varchar(70) NOT NULL,
  `currentVersion` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `migrations_name_version_unique` (`name`,`version`)
) ENGINE=InnoDB AUTO_INCREMENT=92 DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `migrations`
--

LOCK TABLES `migrations` WRITE;
/*!40000 ALTER TABLE `migrations` DISABLE KEYS */;
INSERT INTO `migrations` VALUES (1,'1-create-tables.js','init','3.2'),(2,'2-create-fixtures.js','init','3.2'),(3,'1-post-excerpt.js','1.3','3.2'),(4,'1-codeinjection-post.js','1.4','3.2'),(5,'1-og-twitter-post.js','1.5','3.2'),(6,'1-add-backup-client.js','1.7','3.2'),(7,'1-add-permissions-redirect.js','1.9','3.2'),(8,'1-custom-template-post.js','1.13','3.2'),(9,'2-theme-permissions.js','1.13','3.2'),(10,'1-add-webhooks-table.js','1.18','3.2'),(11,'1-webhook-permissions.js','1.19','3.2'),(12,'1-remove-settings-keys.js','1.20','3.2'),(13,'1-add-contributor-role.js','1.21','3.2'),(14,'1-multiple-authors-DDL.js','1.22','3.2'),(15,'1-multiple-authors-DML.js','1.22','3.2'),(16,'1-update-koenig-beta-html.js','1.25','3.2'),(17,'2-demo-post.js','1.25','3.2'),(18,'1-rename-amp-column.js','2.0','3.2'),(19,'2-update-posts.js','2.0','3.2'),(20,'3-remove-koenig-labs.js','2.0','3.2'),(21,'4-permalink-setting.js','2.0','3.2'),(22,'5-remove-demo-post.js','2.0','3.2'),(23,'6-replace-fixture-posts.js','2.0','3.2'),(24,'1-add-sessions-table.js','2.2','3.2'),(25,'2-add-integrations-and-api-key-tables.js','2.2','3.2'),(26,'3-insert-admin-integration-role.js','2.2','3.2'),(27,'4-insert-integration-and-api-key-permissions.js','2.2','3.2'),(28,'5-add-mobiledoc-revisions-table.js','2.2','3.2'),(29,'1-add-webhook-columns.js','2.3','3.2'),(30,'2-add-webhook-edit-permission.js','2.3','3.2'),(31,'1-add-webhook-permission-roles.js','2.6','3.2'),(32,'1-add-members-table.js','2.8','3.2'),(33,'1-remove-empty-strings.js','2.13','3.2'),(34,'1-add-actions-table.js','2.14','3.2'),(35,'2-add-actions-permissions.js','2.14','3.2'),(36,'1-add-type-column-to-integrations.js','2.15','3.2'),(37,'2-insert-zapier-integration.js','2.15','3.2'),(38,'1-add-members-perrmissions.js','2.16','3.2'),(39,'1-normalize-settings.js','2.17','3.2'),(40,'2-posts-add-canonical-url.js','2.17','3.2'),(41,'1-restore-settings-from-backup.js','2.18','3.2'),(42,'1-update-editor-permissions.js','2.21','3.2'),(43,'1-add-member-permissions-to-roles.js','2.22','3.2'),(44,'1-insert-ghost-db-backup-role.js','2.27','3.2'),(45,'2-insert-db-backup-integration.js','2.27','3.2'),(46,'3-add-subdirectory-to-relative-canonical-urls.js','2.27','3.2'),(47,'1-add-db-backup-content-permission.js','2.28','3.2'),(48,'2-add-db-backup-content-permission-to-roles.js','2.28','3.2'),(49,'3-insert-ghost-scheduler-role.js','2.28','3.2'),(50,'4-insert-scheduler-integration.js','2.28','3.2'),(51,'5-add-scheduler-permission-to-roles.js','2.28','3.2'),(52,'6-add-type-column.js','2.28','3.2'),(53,'7-populate-type-column.js','2.28','3.2'),(54,'8-remove-page-column.js','2.28','3.2'),(55,'1-add-post-page-column.js','2.29','3.2'),(56,'2-populate-post-page-column.js','2.29','3.2'),(57,'3-remove-page-type-column.js','2.29','3.2'),(58,'1-remove-name-and-password-from-members-table.js','2.31','3.2'),(59,'01-add-members-stripe-customers-table.js','2.32','3.2'),(60,'02-add-name-to-members-table.js','2.32','3.2'),(61,'01-correct-members-stripe-customers-table.js','2.33','3.2'),(62,'01-add-stripe-customers-subscriptions-table.js','2.34','3.2'),(63,'02-add-email-to-members-stripe-customers-table.js','2.34','3.2'),(64,'03-add-name-to-members-stripe-customers-table.js','2.34','3.2'),(65,'01-add-note-to-members-table.js','2.35','3.2'),(66,'01-add-self-signup-and-from address-to-members-settings.js','2.37','3.2'),(67,'01-remove-user-ghost-auth-columns.js','3.0','3.2'),(68,'02-drop-token-auth-tables.js','3.0','3.2'),(69,'03-drop-client-auth-tables.js','3.0','3.2'),(70,'04-add-posts-meta-table.js','3.0','3.2'),(71,'05-populate-posts-meta-table.js','3.0','3.2'),(72,'06-remove-posts-meta-columns.js','3.0','3.2'),(73,'07-add-posts-type-column.js','3.0','3.2'),(74,'08-populate-posts-type-column.js','3.0','3.2'),(75,'09-remove-posts-page-column.js','3.0','3.2'),(76,'10-remove-empty-strings.js','3.0','3.2'),(77,'11-update-posts-html.js','3.0','3.2'),(78,'12-populate-members-table-from-subscribers.js','3.0','3.2'),(79,'13-drop-subscribers-table.js','3.0','3.2'),(80,'14-remove-subscribers-flag.js','3.0','3.2'),(81,'01-add-send-email-when-published-to-posts.js','3.1','3.2'),(82,'02-add-email-subject-to-posts-meta.js','3.1','3.2'),(83,'03-add-email-preview-permissions.js','3.1','3.2'),(84,'04-add-subscribed-flag-to-members.js','3.1','3.2'),(85,'05-add-emails-table.js','3.1','3.2'),(86,'06-add-email-permissions.js','3.1','3.2'),(87,'07-add-uuid-field-to-members.js','3.1','3.2'),(88,'08-add-uuid-values-to-members.js','3.1','3.2'),(89,'09-add-further-email-permissions.js','3.1','3.2'),(90,'10-add-email-error-data-column.js','3.1','3.2'),(91,'01-add-cancel-at-period-end-to-subscriptions.js','3.2','3.2');
/*!40000 ALTER TABLE `migrations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `migrations_lock`
--

DROP TABLE IF EXISTS `migrations_lock`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `migrations_lock` (
  `lock_key` varchar(191) NOT NULL,
  `locked` tinyint(1) DEFAULT 0,
  `acquired_at` datetime DEFAULT NULL,
  `released_at` datetime DEFAULT NULL,
  UNIQUE KEY `migrations_lock_lock_key_unique` (`lock_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `migrations_lock`
--

LOCK TABLES `migrations_lock` WRITE;
/*!40000 ALTER TABLE `migrations_lock` DISABLE KEYS */;
INSERT INTO `migrations_lock` VALUES ('km01',0,'2019-12-31 06:10:01','2019-12-31 06:10:26');
/*!40000 ALTER TABLE `migrations_lock` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mobiledoc_revisions`
--

DROP TABLE IF EXISTS `mobiledoc_revisions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mobiledoc_revisions` (
  `id` varchar(24) NOT NULL,
  `post_id` varchar(24) NOT NULL,
  `mobiledoc` longtext DEFAULT NULL,
  `created_at_ts` bigint(20) NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `mobiledoc_revisions_post_id_index` (`post_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mobiledoc_revisions`
--

LOCK TABLES `mobiledoc_revisions` WRITE;
/*!40000 ALTER TABLE `mobiledoc_revisions` DISABLE KEYS */;
INSERT INTO `mobiledoc_revisions` VALUES ('5e0b72b3bd3aed420a98916f','5e0b72b3bd3aed420a98916d','{\"version\":\"0.3.1\",\"atoms\":[],\"cards\":[],\"markups\":[],\"sections\":[[1,\"p\",[[0,[],0,\"T\"]]]]}',1577808563735,'2019-12-31 16:09:23'),('5e0b72bdbd3aed420a989171','5e0b72b3bd3aed420a98916d','{\"version\":\"0.3.1\",\"atoms\":[],\"cards\":[],\"markups\":[],\"sections\":[[1,\"p\",[]]]}',1577808573487,'2019-12-31 16:09:33'),('5e0b72d6bd3aed420a989174','5e0b72b3bd3aed420a98916d','{\"version\":\"0.3.1\",\"atoms\":[],\"cards\":[],\"markups\":[],\"sections\":[[1,\"p\",[[0,[],0,\"I am attempting to measure the performance of Ghost.js wrt. applying hfsort\"]]]]}',1577808598940,'2019-12-31 16:09:58'),('5e0b7307bd3aed420a989176','5e0b72b3bd3aed420a98916d','{\"version\":\"0.3.1\",\"atoms\":[],\"cards\":[],\"markups\":[],\"sections\":[[1,\"p\",[[0,[],0,\"I am attempting to measure the performance of Ghost.js wrt. applying hfsort to Node.js. I cannot find the database Ghost.js is supposed to create. Maybe I should install it globally rather than locally.\"]]]]}',1577808647837,'2019-12-31 16:10:47');
/*!40000 ALTER TABLE `mobiledoc_revisions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `permissions`
--

DROP TABLE IF EXISTS `permissions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `permissions` (
  `id` varchar(24) NOT NULL,
  `name` varchar(50) NOT NULL,
  `object_type` varchar(50) NOT NULL,
  `action_type` varchar(50) NOT NULL,
  `object_id` varchar(24) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `permissions_name_unique` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `permissions`
--

LOCK TABLES `permissions` WRITE;
/*!40000 ALTER TABLE `permissions` DISABLE KEYS */;
INSERT INTO `permissions` VALUES ('5e0ae63f9518860c8fd3fd5d','Export database','db','exportContent',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd5e','Import database','db','importContent',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd5f','Delete all content','db','deleteAllContent',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd60','Send mail','mail','send',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd61','Browse notifications','notification','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd62','Add notifications','notification','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd63','Delete notifications','notification','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd64','Browse posts','post','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd65','Read posts','post','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd66','Edit posts','post','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd67','Add posts','post','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd68','Delete posts','post','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd69','Browse settings','setting','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd6a','Read settings','setting','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd6b','Edit settings','setting','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd6c','Generate slugs','slug','generate',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd6d','Browse tags','tag','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd6e','Read tags','tag','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd6f','Edit tags','tag','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd70','Add tags','tag','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd71','Delete tags','tag','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd72','Browse themes','theme','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd73','Edit themes','theme','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd74','Activate themes','theme','activate',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd75','Upload themes','theme','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd76','Download themes','theme','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd77','Delete themes','theme','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd78','Browse users','user','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd79','Read users','user','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd7a','Edit users','user','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd7b','Add users','user','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd7c','Delete users','user','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd7d','Assign a role','role','assign',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd7e','Browse roles','role','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd7f','Browse invites','invite','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd80','Read invites','invite','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd81','Edit invites','invite','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd82','Add invites','invite','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd83','Delete invites','invite','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd84','Download redirects','redirect','download',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd85','Upload redirects','redirect','upload',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd86','Add webhooks','webhook','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd87','Edit webhooks','webhook','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd88','Delete webhooks','webhook','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd89','Browse integrations','integration','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd8a','Read integrations','integration','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd8b','Edit integrations','integration','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd8c','Add integrations','integration','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd8d','Delete integrations','integration','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd8e','Browse API keys','api_key','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd8f','Read API keys','api_key','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd90','Edit API keys','api_key','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd91','Add API keys','api_key','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd92','Delete API keys','api_key','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd93','Browse Actions','action','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd94','Browse Members','member','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd95','Read Members','member','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd96','Edit Members','member','edit',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd97','Add Members','member','add',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd98','Delete Members','member','destroy',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd99','Publish posts','post','publish',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd9a','Backup database','db','backupContent',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd9b','Email preview','email_preview','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd9c','Send test email','email_preview','sendTestEmail',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd9d','Browse emails','email','browse',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd9e','Read emails','email','read',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd9f','Retry emails','email','retry',NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1');
/*!40000 ALTER TABLE `permissions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `permissions_apps`
--

DROP TABLE IF EXISTS `permissions_apps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `permissions_apps` (
  `id` varchar(24) NOT NULL,
  `app_id` varchar(24) NOT NULL,
  `permission_id` varchar(24) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `permissions_apps`
--

LOCK TABLES `permissions_apps` WRITE;
/*!40000 ALTER TABLE `permissions_apps` DISABLE KEYS */;
/*!40000 ALTER TABLE `permissions_apps` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `permissions_roles`
--

DROP TABLE IF EXISTS `permissions_roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `permissions_roles` (
  `id` varchar(24) NOT NULL,
  `role_id` varchar(24) NOT NULL,
  `permission_id` varchar(24) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `permissions_roles`
--

LOCK TABLES `permissions_roles` WRITE;
/*!40000 ALTER TABLE `permissions_roles` DISABLE KEYS */;
INSERT INTO `permissions_roles` VALUES ('5e0ae6529518860c8fd3fdb5','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd5d'),('5e0ae6529518860c8fd3fdb6','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd5e'),('5e0ae6529518860c8fd3fdb7','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd5f'),('5e0ae6529518860c8fd3fdb8','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd9a'),('5e0ae6529518860c8fd3fdb9','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd60'),('5e0ae6529518860c8fd3fdba','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd61'),('5e0ae6529518860c8fd3fdbb','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd62'),('5e0ae6529518860c8fd3fdbc','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd63'),('5e0ae6529518860c8fd3fdbd','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd64'),('5e0ae6529518860c8fd3fdbe','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd65'),('5e0ae6529518860c8fd3fdbf','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd66'),('5e0ae6529518860c8fd3fdc0','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd67'),('5e0ae6529518860c8fd3fdc1','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd68'),('5e0ae6529518860c8fd3fdc2','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd99'),('5e0ae6529518860c8fd3fdc3','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd69'),('5e0ae6529518860c8fd3fdc4','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd6a'),('5e0ae6529518860c8fd3fdc5','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd6b'),('5e0ae6529518860c8fd3fdc6','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd6c'),('5e0ae6529518860c8fd3fdc7','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd6d'),('5e0ae6529518860c8fd3fdc8','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd6e'),('5e0ae6529518860c8fd3fdc9','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd6f'),('5e0ae6529518860c8fd3fdca','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd70'),('5e0ae6529518860c8fd3fdcb','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd71'),('5e0ae6529518860c8fd3fdcc','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd72'),('5e0ae6529518860c8fd3fdcd','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd73'),('5e0ae6529518860c8fd3fdce','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd74'),('5e0ae6529518860c8fd3fdcf','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd75'),('5e0ae6529518860c8fd3fdd0','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd76'),('5e0ae6529518860c8fd3fdd1','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd77'),('5e0ae6529518860c8fd3fdd2','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd78'),('5e0ae6529518860c8fd3fdd3','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd79'),('5e0ae6529518860c8fd3fdd4','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd7a'),('5e0ae6529518860c8fd3fdd5','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd7b'),('5e0ae6529518860c8fd3fdd6','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd7c'),('5e0ae6529518860c8fd3fdd7','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd7d'),('5e0ae6529518860c8fd3fdd8','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd7e'),('5e0ae6529518860c8fd3fdd9','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd7f'),('5e0ae6529518860c8fd3fdda','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd80'),('5e0ae6529518860c8fd3fddb','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd81'),('5e0ae6529518860c8fd3fddc','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd82'),('5e0ae6529518860c8fd3fddd','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd83'),('5e0ae6529518860c8fd3fdde','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd84'),('5e0ae6529518860c8fd3fddf','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd85'),('5e0ae6529518860c8fd3fde0','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd86'),('5e0ae6529518860c8fd3fde1','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd87'),('5e0ae6529518860c8fd3fde2','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd88'),('5e0ae6529518860c8fd3fde3','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd89'),('5e0ae6529518860c8fd3fde4','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd8a'),('5e0ae6529518860c8fd3fde5','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd8b'),('5e0ae6529518860c8fd3fde6','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd8c'),('5e0ae6529518860c8fd3fde7','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd8d'),('5e0ae6529518860c8fd3fde8','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd8e'),('5e0ae6529518860c8fd3fde9','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd8f'),('5e0ae6529518860c8fd3fdea','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd90'),('5e0ae6529518860c8fd3fdeb','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd91'),('5e0ae6529518860c8fd3fdec','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd92'),('5e0ae6529518860c8fd3fded','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd93'),('5e0ae6529518860c8fd3fdee','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd94'),('5e0ae6529518860c8fd3fdef','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd95'),('5e0ae6529518860c8fd3fdf0','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd96'),('5e0ae6529518860c8fd3fdf1','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd97'),('5e0ae6529518860c8fd3fdf2','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd98'),('5e0ae6529518860c8fd3fdf3','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd9b'),('5e0ae6529518860c8fd3fdf4','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd9c'),('5e0ae6529518860c8fd3fdf5','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd9d'),('5e0ae6529518860c8fd3fdf6','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd9e'),('5e0ae6529518860c8fd3fdf7','5e0ae63f9518860c8fd3fd55','5e0ae63f9518860c8fd3fd9f'),('5e0ae6529518860c8fd3fdf8','5e0ae63f9518860c8fd3fd5b','5e0ae63f9518860c8fd3fd5d'),('5e0ae6529518860c8fd3fdf9','5e0ae63f9518860c8fd3fd5b','5e0ae63f9518860c8fd3fd5e'),('5e0ae6529518860c8fd3fdfa','5e0ae63f9518860c8fd3fd5b','5e0ae63f9518860c8fd3fd5f'),('5e0ae6529518860c8fd3fdfb','5e0ae63f9518860c8fd3fd5b','5e0ae63f9518860c8fd3fd9a'),('5e0ae6529518860c8fd3fdfc','5e0ae63f9518860c8fd3fd5c','5e0ae63f9518860c8fd3fd99'),('5e0ae6529518860c8fd3fdfd','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd60'),('5e0ae6529518860c8fd3fdfe','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd61'),('5e0ae6529518860c8fd3fdff','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd62'),('5e0ae6529518860c8fd3fe00','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd63'),('5e0ae6529518860c8fd3fe01','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd64'),('5e0ae6529518860c8fd3fe02','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd65'),('5e0ae6529518860c8fd3fe03','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd66'),('5e0ae6529518860c8fd3fe04','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd67'),('5e0ae6529518860c8fd3fe05','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd68'),('5e0ae6529518860c8fd3fe06','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd99'),('5e0ae6529518860c8fd3fe07','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd69'),('5e0ae6529518860c8fd3fe08','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd6a'),('5e0ae6529518860c8fd3fe09','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd6b'),('5e0ae6529518860c8fd3fe0a','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd6c'),('5e0ae6529518860c8fd3fe0b','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd6d'),('5e0ae6529518860c8fd3fe0c','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd6e'),('5e0ae6529518860c8fd3fe0d','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd6f'),('5e0ae6529518860c8fd3fe0e','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd70'),('5e0ae6529518860c8fd3fe0f','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd71'),('5e0ae6529518860c8fd3fe10','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd72'),('5e0ae6529518860c8fd3fe11','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd73'),('5e0ae6529518860c8fd3fe12','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd74'),('5e0ae6529518860c8fd3fe13','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd75'),('5e0ae6529518860c8fd3fe14','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd76'),('5e0ae6529518860c8fd3fe15','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd77'),('5e0ae6529518860c8fd3fe16','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd78'),('5e0ae6529518860c8fd3fe17','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd79'),('5e0ae6529518860c8fd3fe18','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd7a'),('5e0ae6529518860c8fd3fe19','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd7b'),('5e0ae6529518860c8fd3fe1a','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd7c'),('5e0ae6529518860c8fd3fe1b','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd7d'),('5e0ae6529518860c8fd3fe1c','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd7e'),('5e0ae6529518860c8fd3fe1d','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd7f'),('5e0ae6529518860c8fd3fe1e','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd80'),('5e0ae6529518860c8fd3fe1f','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd81'),('5e0ae6529518860c8fd3fe20','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd82'),('5e0ae6529518860c8fd3fe21','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd83'),('5e0ae6529518860c8fd3fe22','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd84'),('5e0ae6529518860c8fd3fe23','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd85'),('5e0ae6529518860c8fd3fe24','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd86'),('5e0ae6529518860c8fd3fe25','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd87'),('5e0ae6529518860c8fd3fe26','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd88'),('5e0ae6529518860c8fd3fe27','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd93'),('5e0ae6529518860c8fd3fe28','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd94'),('5e0ae6529518860c8fd3fe29','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd95'),('5e0ae6529518860c8fd3fe2a','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd96'),('5e0ae6529518860c8fd3fe2b','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd97'),('5e0ae6529518860c8fd3fe2c','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd98'),('5e0ae6529518860c8fd3fe2d','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd9b'),('5e0ae6529518860c8fd3fe2e','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd9c'),('5e0ae6529518860c8fd3fe2f','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd9d'),('5e0ae6529518860c8fd3fe30','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd9e'),('5e0ae6529518860c8fd3fe31','5e0ae63f9518860c8fd3fd5a','5e0ae63f9518860c8fd3fd9f'),('5e0ae6529518860c8fd3fe32','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd61'),('5e0ae6529518860c8fd3fe33','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd62'),('5e0ae6529518860c8fd3fe34','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd63'),('5e0ae6529518860c8fd3fe35','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd64'),('5e0ae6529518860c8fd3fe36','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd65'),('5e0ae6529518860c8fd3fe37','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd66'),('5e0ae6529518860c8fd3fe38','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd67'),('5e0ae6529518860c8fd3fe39','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd68'),('5e0ae6529518860c8fd3fe3a','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd99'),('5e0ae6529518860c8fd3fe3b','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd69'),('5e0ae6529518860c8fd3fe3c','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd6a'),('5e0ae6529518860c8fd3fe3d','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd6c'),('5e0ae6529518860c8fd3fe3e','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd6d'),('5e0ae6529518860c8fd3fe3f','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd6e'),('5e0ae6529518860c8fd3fe40','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd6f'),('5e0ae6529518860c8fd3fe41','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd70'),('5e0ae6529518860c8fd3fe42','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd71'),('5e0ae6529518860c8fd3fe43','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd78'),('5e0ae6529518860c8fd3fe44','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd79'),('5e0ae6529518860c8fd3fe45','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd7a'),('5e0ae6529518860c8fd3fe46','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd7b'),('5e0ae6529518860c8fd3fe47','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd7c'),('5e0ae6529518860c8fd3fe48','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd7d'),('5e0ae6529518860c8fd3fe49','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd7e'),('5e0ae6529518860c8fd3fe4a','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd7f'),('5e0ae6529518860c8fd3fe4b','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd80'),('5e0ae6529518860c8fd3fe4c','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd81'),('5e0ae6529518860c8fd3fe4d','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd82'),('5e0ae6529518860c8fd3fe4e','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd83'),('5e0ae6529518860c8fd3fe4f','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd72'),('5e0ae6529518860c8fd3fe50','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd9b'),('5e0ae6529518860c8fd3fe51','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd9c'),('5e0ae6529518860c8fd3fe52','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd9d'),('5e0ae6529518860c8fd3fe53','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd9e'),('5e0ae6529518860c8fd3fe54','5e0ae63f9518860c8fd3fd56','5e0ae63f9518860c8fd3fd9f'),('5e0ae6529518860c8fd3fe55','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd64'),('5e0ae6529518860c8fd3fe56','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd65'),('5e0ae6529518860c8fd3fe57','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd67'),('5e0ae6529518860c8fd3fe58','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd69'),('5e0ae6529518860c8fd3fe59','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd6a'),('5e0ae6529518860c8fd3fe5a','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd6c'),('5e0ae6529518860c8fd3fe5b','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd6d'),('5e0ae6529518860c8fd3fe5c','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd6e'),('5e0ae6529518860c8fd3fe5d','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd70'),('5e0ae6529518860c8fd3fe5e','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd78'),('5e0ae6529518860c8fd3fe5f','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd79'),('5e0ae6529518860c8fd3fe60','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd7e'),('5e0ae6529518860c8fd3fe61','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd72'),('5e0ae6529518860c8fd3fe62','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd9b'),('5e0ae6529518860c8fd3fe63','5e0ae63f9518860c8fd3fd57','5e0ae63f9518860c8fd3fd9e'),('5e0ae6529518860c8fd3fe64','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd64'),('5e0ae6529518860c8fd3fe65','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd65'),('5e0ae6529518860c8fd3fe66','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd67'),('5e0ae6529518860c8fd3fe67','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd69'),('5e0ae6529518860c8fd3fe68','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd6a'),('5e0ae6529518860c8fd3fe69','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd6c'),('5e0ae6529518860c8fd3fe6a','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd6d'),('5e0ae6529518860c8fd3fe6b','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd6e'),('5e0ae6529518860c8fd3fe6c','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd78'),('5e0ae6529518860c8fd3fe6d','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd79'),('5e0ae6529518860c8fd3fe6e','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd7e'),('5e0ae6529518860c8fd3fe6f','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd72'),('5e0ae6529518860c8fd3fe70','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd9b'),('5e0ae6529518860c8fd3fe71','5e0ae63f9518860c8fd3fd58','5e0ae63f9518860c8fd3fd9e');
/*!40000 ALTER TABLE `permissions_roles` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `permissions_users`
--

DROP TABLE IF EXISTS `permissions_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `permissions_users` (
  `id` varchar(24) NOT NULL,
  `user_id` varchar(24) NOT NULL,
  `permission_id` varchar(24) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `permissions_users`
--

LOCK TABLES `permissions_users` WRITE;
/*!40000 ALTER TABLE `permissions_users` DISABLE KEYS */;
/*!40000 ALTER TABLE `permissions_users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `posts`
--

DROP TABLE IF EXISTS `posts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `posts` (
  `id` varchar(24) NOT NULL,
  `uuid` varchar(36) NOT NULL,
  `title` varchar(2000) NOT NULL,
  `slug` varchar(191) NOT NULL,
  `mobiledoc` longtext DEFAULT NULL,
  `html` longtext DEFAULT NULL,
  `comment_id` varchar(50) DEFAULT NULL,
  `plaintext` longtext DEFAULT NULL,
  `feature_image` varchar(2000) DEFAULT NULL,
  `featured` tinyint(1) NOT NULL DEFAULT 0,
  `type` varchar(50) NOT NULL DEFAULT 'post',
  `status` varchar(50) NOT NULL DEFAULT 'draft',
  `locale` varchar(6) DEFAULT NULL,
  `visibility` varchar(50) NOT NULL DEFAULT 'public',
  `send_email_when_published` tinyint(1) DEFAULT 0,
  `author_id` varchar(24) NOT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  `published_at` datetime DEFAULT NULL,
  `published_by` varchar(24) DEFAULT NULL,
  `custom_excerpt` varchar(2000) DEFAULT NULL,
  `codeinjection_head` text DEFAULT NULL,
  `codeinjection_foot` text DEFAULT NULL,
  `custom_template` varchar(100) DEFAULT NULL,
  `canonical_url` text DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `posts_slug_unique` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `posts`
--

LOCK TABLES `posts` WRITE;
/*!40000 ALTER TABLE `posts` DISABLE KEYS */;
INSERT INTO `posts` VALUES ('5e0b72b3bd3aed420a98916d','2e54239d-e92e-4196-84e3-81560f199327','Test Post','test-post','{\"version\":\"0.3.1\",\"atoms\":[],\"cards\":[],\"markups\":[],\"sections\":[[1,\"p\",[[0,[],0,\"I am attempting to measure the performance of Ghost.js wrt. applying hfsort to Node.js. I cannot find the database Ghost.js is supposed to create. Maybe I should install it globally rather than locally.\"]]]]}','<p>I am attempting to measure the performance of Ghost.js wrt. applying hfsort to Node.js. I cannot find the database Ghost.js is supposed to create. Maybe I should install it globally rather than locally.</p>','5e0b72b3bd3aed420a98916d','I am attempting to measure the performance of Ghost.js wrt. applying hfsort to\nNode.js. I cannot find the database Ghost.js is supposed to create. Maybe I\nshould install it globally rather than locally.',NULL,0,'post','published',NULL,'public',0,'1','2019-12-31 16:09:23','1','2019-12-31 16:10:52','1','2019-12-31 16:10:52','1',NULL,NULL,NULL,NULL,NULL);
/*!40000 ALTER TABLE `posts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `posts_authors`
--

DROP TABLE IF EXISTS `posts_authors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `posts_authors` (
  `id` varchar(24) NOT NULL,
  `post_id` varchar(24) NOT NULL,
  `author_id` varchar(24) NOT NULL,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `posts_authors_post_id_foreign` (`post_id`),
  KEY `posts_authors_author_id_foreign` (`author_id`),
  CONSTRAINT `posts_authors_author_id_foreign` FOREIGN KEY (`author_id`) REFERENCES `users` (`id`),
  CONSTRAINT `posts_authors_post_id_foreign` FOREIGN KEY (`post_id`) REFERENCES `posts` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `posts_authors`
--

LOCK TABLES `posts_authors` WRITE;
/*!40000 ALTER TABLE `posts_authors` DISABLE KEYS */;
INSERT INTO `posts_authors` VALUES ('5e0b72b3bd3aed420a98916e','5e0b72b3bd3aed420a98916d','1',0);
/*!40000 ALTER TABLE `posts_authors` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `posts_meta`
--

DROP TABLE IF EXISTS `posts_meta`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `posts_meta` (
  `id` varchar(24) NOT NULL,
  `post_id` varchar(24) NOT NULL,
  `og_image` varchar(2000) DEFAULT NULL,
  `og_title` varchar(300) DEFAULT NULL,
  `og_description` varchar(500) DEFAULT NULL,
  `twitter_image` varchar(2000) DEFAULT NULL,
  `twitter_title` varchar(300) DEFAULT NULL,
  `twitter_description` varchar(500) DEFAULT NULL,
  `meta_title` varchar(2000) DEFAULT NULL,
  `meta_description` varchar(2000) DEFAULT NULL,
  `email_subject` varchar(300) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `posts_meta_post_id_unique` (`post_id`),
  CONSTRAINT `posts_meta_post_id_foreign` FOREIGN KEY (`post_id`) REFERENCES `posts` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `posts_meta`
--

LOCK TABLES `posts_meta` WRITE;
/*!40000 ALTER TABLE `posts_meta` DISABLE KEYS */;
/*!40000 ALTER TABLE `posts_meta` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `posts_tags`
--

DROP TABLE IF EXISTS `posts_tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `posts_tags` (
  `id` varchar(24) NOT NULL,
  `post_id` varchar(24) NOT NULL,
  `tag_id` varchar(24) NOT NULL,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `posts_tags_post_id_foreign` (`post_id`),
  KEY `posts_tags_tag_id_foreign` (`tag_id`),
  CONSTRAINT `posts_tags_post_id_foreign` FOREIGN KEY (`post_id`) REFERENCES `posts` (`id`),
  CONSTRAINT `posts_tags_tag_id_foreign` FOREIGN KEY (`tag_id`) REFERENCES `tags` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `posts_tags`
--

LOCK TABLES `posts_tags` WRITE;
/*!40000 ALTER TABLE `posts_tags` DISABLE KEYS */;
/*!40000 ALTER TABLE `posts_tags` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `roles`
--

DROP TABLE IF EXISTS `roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `roles` (
  `id` varchar(24) NOT NULL,
  `name` varchar(50) NOT NULL,
  `description` varchar(2000) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `roles_name_unique` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `roles`
--

LOCK TABLES `roles` WRITE;
/*!40000 ALTER TABLE `roles` DISABLE KEYS */;
INSERT INTO `roles` VALUES ('5e0ae63f9518860c8fd3fd55','Administrator','Administrators','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd56','Editor','Editors','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd57','Author','Authors','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd58','Contributor','Contributors','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd59','Owner','Blog Owner','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd5a','Admin Integration','External Apps','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd5b','DB Backup Integration','Internal DB Backup Client','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1'),('5e0ae63f9518860c8fd3fd5c','Scheduler Integration','Internal Scheduler Client','2019-12-31 06:10:07','1','2019-12-31 06:10:07','1');
/*!40000 ALTER TABLE `roles` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `roles_users`
--

DROP TABLE IF EXISTS `roles_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `roles_users` (
  `id` varchar(24) NOT NULL,
  `role_id` varchar(24) NOT NULL,
  `user_id` varchar(24) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `roles_users`
--

LOCK TABLES `roles_users` WRITE;
/*!40000 ALTER TABLE `roles_users` DISABLE KEYS */;
INSERT INTO `roles_users` VALUES ('5e0ae6529518860c8fd3fda0','5e0ae63f9518860c8fd3fd57','5951f5fca366002ebd5dbef7'),('5e0ae6529518860c8fd3fe79','5e0ae63f9518860c8fd3fd59','1');
/*!40000 ALTER TABLE `roles_users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `sessions`
--

DROP TABLE IF EXISTS `sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `sessions` (
  `id` varchar(24) NOT NULL,
  `session_id` varchar(32) NOT NULL,
  `user_id` varchar(24) NOT NULL,
  `session_data` varchar(2000) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `sessions_session_id_unique` (`session_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `sessions`
--

LOCK TABLES `sessions` WRITE;
/*!40000 ALTER TABLE `sessions` DISABLE KEYS */;
INSERT INTO `sessions` VALUES ('5e0b723abd3aed420a989164','WPOzVNMDJjxND6XdV5hRRpcxvi1GQpCq','1','{\"cookie\":{\"originalMaxAge\":15768000000,\"expires\":\"2020-07-01T04:07:22.517Z\",\"secure\":false,\"httpOnly\":true,\"path\":\"/ghost\",\"sameSite\":\"lax\"},\"user_id\":\"1\",\"origin\":\"http://localhost:2368\",\"user_agent\":\"Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:71.0) Gecko/20100101 Firefox/71.0\",\"ip\":\"127.0.0.1\"}','2019-12-31 16:07:22','2019-12-31 16:07:22');
/*!40000 ALTER TABLE `sessions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `settings`
--

DROP TABLE IF EXISTS `settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `settings` (
  `id` varchar(24) NOT NULL,
  `key` varchar(50) NOT NULL,
  `value` text DEFAULT NULL,
  `type` varchar(50) NOT NULL DEFAULT 'core',
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `settings_key_unique` (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `settings`
--

LOCK TABLES `settings` WRITE;
/*!40000 ALTER TABLE `settings` DISABLE KEYS */;
INSERT INTO `settings` VALUES ('5e0ae6539518860c8fd3fe7a','db_hash','623b3e9d-c92e-4179-a3e9-ea407c3b72b9','core','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe7b','next_update_check','1577894816','core','2019-12-31 06:10:27','1','2019-12-31 16:06:55','1'),('5e0ae6539518860c8fd3fe7c','notifications','[{\"dismissible\":true,\"location\":\"bottom\",\"status\":\"alert\",\"id\":\"5e0b723abd3aed420a989163\",\"type\":\"warn\",\"message\":\"Ghost is currently unable to send email. See https://ghost.org/docs/concepts/config/#mail for instructions.\",\"seen\":false,\"addedAt\":\"2019-12-31T16:07:22.426Z\"}]','core','2019-12-31 06:10:27','1','2019-12-31 16:07:22','1'),('5e0ae6539518860c8fd3fe7d','session_secret','40dced55c2332d66fd3fcbdc73c3d6d2660baf1746f7c44236851aa6d9e2cec0','core','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe7e','theme_session_secret','f7c35a5a834f2cfa6c2b11f93006e9acf1dd836bc89ae260e239016afc3b5a04','core','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe7f','title','My Awesome Site','blog','2019-12-31 06:10:27','1','2019-12-31 16:07:22','1'),('5e0ae6539518860c8fd3fe80','description','Thoughts, stories and ideas.','blog','2019-12-31 06:10:27','1','2019-12-31 16:07:22','1'),('5e0ae6539518860c8fd3fe81','logo','https://static.ghost.org/v1.0.0/images/ghost-logo.svg','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe82','cover_image','https://static.ghost.org/v3.0.0/images/publication-cover.png','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe83','icon',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe84','brand','{\"primaryColor\":\"\"}','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe85','default_locale','en','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe86','active_timezone','Etc/UTC','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe87','force_i18n','true','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe88','permalinks','/:slug/','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe89','amp','true','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe8a','ghost_head',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe8b','ghost_foot',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe8c','facebook','ghost','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe8d','twitter','tryghost','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe8e','labs','{}','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe8f','navigation','[{\"label\":\"Home\", \"url\":\"/\"},{\"label\":\"Tag\", \"url\":\"/tag/getting-started/\"}, {\"label\":\"Author\", \"url\":\"/author/ghost/\"},{\"label\":\"Help\", \"url\":\"https://ghost.org/docs/\"}]','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe90','secondary_navigation','[]','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe91','slack','[{\"url\":\"\", \"username\":\"Ghost\"}]','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe92','unsplash','{\"isActive\": true}','blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe93','meta_title',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe94','meta_description',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe95','og_image',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe96','og_title',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe97','og_description',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe98','twitter_image',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe99','twitter_title',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe9a','twitter_description',NULL,'blog','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe9b','active_theme','casper','theme','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe9c','is_private','false','private','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe9d','password',NULL,'private','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe9e','public_hash','58697fa9b66609b38d887184759d0f','private','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fe9f','members_public_key','-----BEGIN RSA PUBLIC KEY-----\nMIGJAoGBAKLZGRuhB1hD4H+x4DHDFOYt3VUEGJFeT+SWdmIJ8aqbqTYzbmZuuhpbM+mI8RtE\nog1OTbfzDGLXurHTZdkA4w2rw/toey6Vv6C0DsrpqNv5fYHJ6f85tfDEV02CGWs0HnL1KrBK\n44NvYEtG4yNiNcytsNH1yVYw4j9qm8KmIYeXAgMBAAE=\n-----END RSA PUBLIC KEY-----\n','members','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fea0','members_private_key','-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQCi2RkboQdYQ+B/seAxwxTmLd1VBBiRXk/klnZiCfGqm6k2M25mbroaWzPp\niPEbRKINTk238wxi17qx02XZAOMNq8P7aHsulb+gtA7K6ajb+X2Byen/ObXwxFdNghlrNB5y\n9SqwSuODb2BLRuMjYjXMrbDR9clWMOI/apvCpiGHlwIDAQABAoGBAJJN12fiKRYcjVJL/W7X\npCwUIphhwKzBfaeRojP8WRj9Fm3ykQoICrzpGV+Dv5HO/IRVyC8udf9Lb5iZoxPt3w4TMf+4\nV6qYqP8BlE8lvZDUXyzka0l0yayRRg73EYZ3Zh+EaFD6VsQPwrjV0+oxx+OgnkdoFtYCvan3\n4nLX2LcpAkEA7T0CnLq/hzIk0ZI6n9/8vUlpVdy/89QTFk5xV/jsup4rMfCG5qc6XbcyPOIm\nBIkCUVIRf8kAiJ2gEwFhYv3D8wJBAK+6Bnfz880YyIx5nNKwL77ZY3O3V4Z2CVZaJbaMhiPq\nGq5n5CcZzOzq2TfcvKCDzi4v6EyVCEeRXTeKMaJTas0CQGvUe0d5qmxs4kdPS843JM10fKhG\nOgk9r59H8ESoJBF+qut8BBT6lZDbH76Em/sbuy3zO3j1h4SRAJ0i130DEvkCQQCugxOBdKed\n+wrPVsbDBW2lHsaBWIZ3ZimHtCbXz143tHmi0lHl8t1sOx5VN8WrsrnDbJhJ1YdPa7EjQv5f\nsm/RAkArJn+RzF6wfmaiQwCjq5rJRer2qg6+lYqjH44Kt6VbYthBDlXi6Pl/VnMIf/oe7HN1\ncgtD9l3sWECRY02HgYfX\n-----END RSA PRIVATE KEY-----\n','members','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fea1','members_session_secret','5dfd02612390c15c5044e83c774daece6d83dd660cb7624b66e650ef7c132371','members','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fea2','members_email_auth_secret','56e3fd5f096e94c7d49be187151b43457dc69b264f86b75341927ed082df37db80c30015b565bf6f89230194d3ccb61b5164f653dcd447a23d9c11ed253046d8','members','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fea3','default_content_visibility','public','members','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fea4','members_subscription_settings','{\"isPaid\":false,\"fromAddress\":\"noreply\",\"allowSelfSignup\":true,\"paymentProcessors\":[{\"adapter\":\"stripe\",\"config\":{\"secret_token\":\"\",\"public_token\":\"\",\"product\":{\"name\":\"Ghost Subscription\"},\"plans\":[{\"name\":\"Monthly\",\"currency\":\"usd\",\"interval\":\"month\",\"amount\":\"\"},{\"name\":\"Yearly\",\"currency\":\"usd\",\"interval\":\"year\",\"amount\":\"\"}]}}]}','members','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1'),('5e0ae6539518860c8fd3fea5','bulk_email_settings','{\"provider\":\"mailgun\", \"apiKey\": \"\", \"domain\": \"\", \"baseUrl\": \"\"}','bulk_email','2019-12-31 06:10:27','1','2019-12-31 06:10:27','1');
/*!40000 ALTER TABLE `settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `tags`
--

DROP TABLE IF EXISTS `tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tags` (
  `id` varchar(24) NOT NULL,
  `name` varchar(191) NOT NULL,
  `slug` varchar(191) NOT NULL,
  `description` text DEFAULT NULL,
  `feature_image` varchar(2000) DEFAULT NULL,
  `parent_id` varchar(191) DEFAULT NULL,
  `visibility` varchar(50) NOT NULL DEFAULT 'public',
  `meta_title` varchar(2000) DEFAULT NULL,
  `meta_description` varchar(2000) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `tags_slug_unique` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `tags`
--

LOCK TABLES `tags` WRITE;
/*!40000 ALTER TABLE `tags` DISABLE KEYS */;
INSERT INTO `tags` VALUES ('5e0ae63f9518860c8fd3fd54','Getting Started','getting-started',NULL,NULL,NULL,'public',NULL,NULL,'2019-12-31 06:10:07','1','2019-12-31 06:10:07','1');
/*!40000 ALTER TABLE `tags` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `users` (
  `id` varchar(24) NOT NULL,
  `name` varchar(191) NOT NULL,
  `slug` varchar(191) NOT NULL,
  `password` varchar(60) NOT NULL,
  `email` varchar(191) NOT NULL,
  `profile_image` varchar(2000) DEFAULT NULL,
  `cover_image` varchar(2000) DEFAULT NULL,
  `bio` text DEFAULT NULL,
  `website` varchar(2000) DEFAULT NULL,
  `location` text DEFAULT NULL,
  `facebook` varchar(2000) DEFAULT NULL,
  `twitter` varchar(2000) DEFAULT NULL,
  `accessibility` text DEFAULT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'active',
  `locale` varchar(6) DEFAULT NULL,
  `visibility` varchar(50) NOT NULL DEFAULT 'public',
  `meta_title` varchar(2000) DEFAULT NULL,
  `meta_description` varchar(2000) DEFAULT NULL,
  `tour` text DEFAULT NULL,
  `last_seen` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `users_slug_unique` (`slug`),
  UNIQUE KEY `users_email_unique` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES ('1','Nix N. Nix','nix','$2a$10$4QAOEIJwKpZC.wlIVVydJuM4IAxPEbETvW66UzQONdtkqRkiqWeV6','nix@go-nix.ca',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'active',NULL,'public',NULL,NULL,'[\"getting-started\"]','2019-12-31 16:07:22','2019-12-31 06:10:07','1','2019-12-31 16:08:09','1'),('5951f5fca366002ebd5dbef7','Ghost','ghost','$2a$10$G6Zy72h.hF9QuDmZhiNHWeiBVRtNI/ouOa8rqf3WzV.ZTQQxBh39G','ghost-author@example.com','https://static.ghost.org/v3.0.0/images/ghost.png',NULL,'You can delete this user to remove all the welcome posts','https://ghost.org','The Internet','ghost','ghost',NULL,'active',NULL,'public',NULL,NULL,NULL,NULL,'2019-12-31 06:10:16','1','2019-12-31 06:10:16','1');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `webhooks`
--

DROP TABLE IF EXISTS `webhooks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `webhooks` (
  `id` varchar(24) NOT NULL,
  `event` varchar(50) NOT NULL,
  `target_url` varchar(2000) NOT NULL,
  `name` varchar(191) DEFAULT NULL,
  `secret` varchar(191) DEFAULT NULL,
  `api_version` varchar(50) NOT NULL DEFAULT 'v2',
  `integration_id` varchar(24) DEFAULT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'available',
  `last_triggered_at` datetime DEFAULT NULL,
  `last_triggered_status` varchar(50) DEFAULT NULL,
  `last_triggered_error` varchar(50) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `created_by` varchar(24) NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `updated_by` varchar(24) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `webhooks`
--

LOCK TABLES `webhooks` WRITE;
/*!40000 ALTER TABLE `webhooks` DISABLE KEYS */;
/*!40000 ALTER TABLE `webhooks` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2020-01-23 11:10:38

```