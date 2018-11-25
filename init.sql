-- Table: public.loadingscreen

-- DROP TABLE public.loadingscreen;

CREATE TABLE public.loadingscreen
(
    id integer NOT NULL DEFAULT nextval('loadingscreen_id_seq'::regclass),
    up integer NOT NULL DEFAULT 0,
    down integer NOT NULL DEFAULT 0,
    confsort integer,
    accountid bigint NOT NULL,
    url text COLLATE pg_catalog."default" NOT NULL,
    approval boolean,
    approver bigint,
    created timestamp with time zone NOT NULL DEFAULT now(),
    comment text COLLATE pg_catalog."default",
    CONSTRAINT primry PRIMARY KEY (id),
    CONSTRAINT nosimilars UNIQUE (id)
,
    CONSTRAINT unique_url UNIQUE (url)

)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE public.loadingscreen
    OWNER to metastruct;








-- Table: public.loadingscreen_votes

-- DROP TABLE public.loadingscreen_votes;

CREATE TABLE public.loadingscreen_votes
(
    accountid bigint NOT NULL,
    vote boolean,
    id integer NOT NULL,
    "when" timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT primarykeything PRIMARY KEY (id, accountid),
    CONSTRAINT onlyonevote UNIQUE (accountid, id)
,
    CONSTRAINT linktoentry FOREIGN KEY (id)
        REFERENCES public.loadingscreen (id) MATCH SIMPLE
        ON UPDATE CASCADE
        ON DELETE CASCADE
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE public.loadingscreen_votes
    OWNER to metastruct;