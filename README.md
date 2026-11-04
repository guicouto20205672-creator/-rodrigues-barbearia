# Rodrigues Barbearia

Aplicação React + Vite para o site e sistema de agendamento da Rodrigues Barbearia.

## Desenvolvimento local

```bash
npm install
cp .env.example .env
npm run dev
```

Configure as variáveis do Supabase no arquivo .env. Nunca coloque a chave service_role no frontend.

## Estado do projeto

Primeira versão de interface e estrutura. O agendamento real, autenticação, fila FIFO, temporizador de 5 minutos e envio de WhatsApp precisam de backend e configuração antes de produção. A fila deve ser controlada no servidor para evitar ultrapassagem e reservas duplicadas.


GitHub Pages: publicação automatizada via GitHub Actions.
