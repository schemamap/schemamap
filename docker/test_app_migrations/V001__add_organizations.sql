create table organizations (
    id bigserial primary key,
    name text not null unique check (char_length(name) between 3 and 255),
    created_at timestamptz not null default now(),
    website text check (website like 'http%')
);

create table projects (
    id bigserial primary key,
    organization_id bigint references organizations,
    name text not null check (char_length(name) between 1 and 255),
    created_at timestamptz not null default now(),
    description text check(char_length(name) < 400),
    unique (organization_id, name)
);
