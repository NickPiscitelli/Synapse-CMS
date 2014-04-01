create table users (
 user_id int not null auto_increment primary key,
 name varchar(255)  NOT NULL,
 full text,
 password varchar(255),
 is_author TINYINT DEFAULT 0,
 is_admin TINYINT DEFAULT 0,
 created DATETIME DEFAULT 0
)ENGINE=InnoDB;

create table pages (
 page_id int not null auto_increment primary key,
 author_id int not null,
 category int not null,
 name varchar(255),
 title varchar(255),
 html text,
 updated DATETIME DEFAULT 0,
 created DATETIME DEFAULT 0,
 published tinyint not null default 0,
 front_page tinyint not null default 0
)ENGINE=InnoDB;

create table category (
	category_id int NOT NULL auto_increment primary key,
	name varchar(255) NOT NULL
)ENGINE=InnoDB;

create table page_tags (
	page_id int NOT NULL,
	vocab_id int NOT NULL
)ENGINE=InnoDB;

create table vocabulary (
	vocab_id int not null auto_increment primary key,
	term varchar(255) NOT NULL
)ENGINE=InnoDB;

create table menus (
	menu_id int not null auto_increment primary key,
	name varchar(255),
	list text
)ENGINE=InnoDB;

create table slideshows (
	id int not null auto_increment primary key,
	page_id int NOT NULL,
	src varchar(255),
	title varchar(255),
	url varchar(255),
	description text
)ENGINE=InnoDB;
