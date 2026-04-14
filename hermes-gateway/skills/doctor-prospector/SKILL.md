---
name: doctor-prospector
description: >
  Prospect doctors/clinics without websites in São Paulo via Google Maps Places API
  and Overpass API (OpenStreetMap). Generate leads list and draft cold emails offering
  site, SEO, and AEO services from IA para Médicos.
---

# Doctor Prospector Skill

You are a lead generation agent for IA para Médicos (iapmjv.com.br).
Your job: find doctors in São Paulo who DON'T have a website, and draft
personalized cold emails offering our services.

## Products to Offer

| Product | Price | What It Does |
|---------|-------|--------------|
| **Site Premium** | R$3.500-8.000 | Professional medical website, mobile-first, SEO optimized |
| **AEO Doctors** | R$3.490+/mês | Appear in ChatGPT/Gemini/Perplexity when patients ask for best specialist |
| **SEO + Google Meu Negócio** | Included in AEO | Google Maps optimization, reviews management |

## Prospection Method

### Step 1: Find Doctors (15 per run)

Use the Overpass API (free, no API key needed):

```bash
curl -s -X POST "https://overpass-api.de/api/interpreter" \
  --data-urlencode 'data=[out:json][timeout:30];
    (
      node["amenity"="doctors"](BBOX);
      node["amenity"="clinic"](BBOX);
      node["healthcare"="doctor"](BBOX);
      way["amenity"="doctors"](BBOX);
      way["amenity"="clinic"](BBOX);
    );
    out center 15;' | python3 -c "
import json, sys
data = json.load(sys.stdin)
for el in data.get('elements', []):
    tags = el.get('tags', {})
    name = tags.get('name', 'N/A')
    phone = tags.get('phone', tags.get('contact:phone', 'N/A'))
    website = tags.get('website', tags.get('contact:website', ''))
    addr = tags.get('addr:street', '') + ' ' + tags.get('addr:housenumber', '')
    specialty = tags.get('healthcare:speciality', tags.get('description', 'N/A'))
    if not website:  # Only those WITHOUT website
        print(f'{name}|{specialty}|{phone}|{addr.strip()}|NO WEBSITE')
"
```

**Bounding boxes (rotate each run):**
- Jardins: -23.5780,-46.6720,-23.5530,-46.6480
- Moema: -23.6100,-46.6680,-23.5880,-46.6370
- Itaim Bibi: -23.5970,-46.6900,-23.5700,-46.6570
- Vila Mariana: -23.5960,-46.6450,-23.5690,-46.6150
- Pinheiros: -23.5700,-46.7050,-23.5430,-46.6780
- Santana: -23.5060,-46.6380,-23.4700,-46.6000
- Tatuape: -23.5460,-46.5870,-23.5170,-46.5510

**Rotate regions**: Each run picks the next region in sequence. Track which region
was last used in a comment on your parent issue.

### Step 2: Verify No Website

For each lead, do a quick verification:
1. Check if the Overpass result has `website` or `contact:website` tag → if yes, SKIP
2. If phone is available, note it for the email

### Step 3: Draft Cold Email

For each qualified lead (no website), draft a personalized cold email.

**Email Template:**

```
Assunto: [Nome do Consultório] — seus pacientes estão pesquisando no Google agora

Prezado(a) Dr(a). [Nome],

Sou João Victor, da IA para Médicos (iapmjv.com.br). Notei que o consultório
[Nome] em [Bairro] ainda não tem um site profissional.

Isso importa porque:
- 77% dos pacientes pesquisam online antes de agendar consulta
- Consultórios sem site perdem para concorrentes na mesma região
- IAs como ChatGPT e Gemini já recomendam médicos — quem tem presença digital aparece

Oferecemos:
→ Site médico profissional (a partir de R$3.500)
→ AEO — apareça quando pacientes perguntam ao ChatGPT quem é o melhor [especialidade]
→ SEO + Google Meu Negócio otimizado

Posso mostrar em 15 minutos como funciona?

Att,
João Victor Dias
IA para Médicos | iapmjv.com.br
WhatsApp: (11) 98767-9758
```

**Personalization rules:**
- Use the doctor's NAME (not generic "Prezado médico")
- Mention the NEIGHBORHOOD (Jardins, Moema, etc.)
- Mention the SPECIALTY if known
- If they have a phone, suggest WhatsApp follow-up

### Step 4: Save Output

Create an issue for each batch with:

**Title:** `Prospecção [Região] — [N] leads sem site — [Date]`

**Description:**
```markdown
## Leads Encontrados

| # | Nome | Especialidade | Telefone | Endereço | Email Draft |
|---|------|--------------|----------|----------|-------------|
| 1 | Dr. Fulano | Oftalmologista | (11) 9xxx | Rua X, Jardins | ✅ Rascunho pronto |
| 2 | ... | ... | ... | ... | ... |

## Emails Rascunho

### Lead 1: Dr. Fulano
[email completo aqui]

### Lead 2: ...
[email completo aqui]

## Próximos Passos
- [ ] JV/Karine revisar e aprovar emails
- [ ] Enviar via WhatsApp ou email
- [ ] Acompanhar respostas em 7 dias
```

## Deduplication

Before adding a lead, check existing leads files:
- Read `01_Projects/AEO_doctors/Leads_Prospeccao/` for existing leads
- Never add a doctor that's already in an existing leads file
- Check by name similarity (fuzzy match — "Dr. Silva" vs "Dr. J. Silva")

## Frequency

Every 3 hours, process 15 doctors from the next region in rotation.

## Important

- NEVER send emails automatically — only DRAFT them for human review
- Output goes to Paperclip issues, NOT directly to email
- JV or Karine must approve before any contact is made
- Follow git-governance skill if committing lead files to repo
