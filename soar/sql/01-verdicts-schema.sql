--
-- PostgreSQL database dump
--

\restrict pijgCLaSa27DDNcRKFhgyVqeh6duhcIsBOdanumv7AolfhjobHgraMbhCYPitMg

-- Dumped from database version 16.14 (Debian 16.14-1.pgdg13+1)
-- Dumped by pg_dump version 16.14 (Debian 16.14-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: verdicts; Type: TABLE; Schema: public; Owner: soar
--

CREATE TABLE public.verdicts (
    id integer NOT NULL,
    ip text NOT NULL,
    alertname text,
    severity text,
    verdict text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.verdicts OWNER TO soar;

--
-- Name: verdicts_id_seq; Type: SEQUENCE; Schema: public; Owner: soar
--

CREATE SEQUENCE public.verdicts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.verdicts_id_seq OWNER TO soar;

--
-- Name: verdicts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: soar
--

ALTER SEQUENCE public.verdicts_id_seq OWNED BY public.verdicts.id;


--
-- Name: verdicts id; Type: DEFAULT; Schema: public; Owner: soar
--

ALTER TABLE ONLY public.verdicts ALTER COLUMN id SET DEFAULT nextval('public.verdicts_id_seq'::regclass);


--
-- Name: verdicts verdicts_pkey; Type: CONSTRAINT; Schema: public; Owner: soar
--

ALTER TABLE ONLY public.verdicts
    ADD CONSTRAINT verdicts_pkey PRIMARY KEY (id);


--
-- Name: idx_verdicts_ip_time; Type: INDEX; Schema: public; Owner: soar
--

CREATE INDEX idx_verdicts_ip_time ON public.verdicts USING btree (ip, created_at DESC);


--
-- PostgreSQL database dump complete
--

\unrestrict pijgCLaSa27DDNcRKFhgyVqeh6duhcIsBOdanumv7AolfhjobHgraMbhCYPitMg

