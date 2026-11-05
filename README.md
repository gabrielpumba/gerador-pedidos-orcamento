# 📦 Okada Pedidos — Sincronização e Atualização Automática

Repositório oficial de distribuição e atualização automática do sistema **Okada Pedidos** (Okada Representações).

---

## 🚀 Sobre o Sistema

O **Okada Pedidos** é uma plataforma comercial rápida e **100% offline-first** para emissão de pedidos e orçamentos em PDF, gestão de tabelas de preços (normais e promocionais líquidas) e cadastro de clientes/distribuidoras.

### Principais Recursos:
- **Emissão de Pedidos e Orçamentos:** Fluxo guiado por representada, região, cliente, seleção múltipla de tabelas/modalidades de preço, descontos em cascata e prazos de pagamento.
- **Tabelas Promocionais (Preço Líquido):** Proteção automática para itens promocionais contra descontos globais de rodapé.
- **Histórico Editável:** Visualização, reabertura e edição completa de pedidos e orçamentos anteriores.
- **Geração Instantânea de PDF:** Layout comercial padronizado pronto para envio ou impressão.
- **Modo 100% Offline:** Funciona integralmente sem internet após instalado, sincronizando novas versões e tabelas automaticamente quando conectado.

---

## 💻 Como Instalar no Computador (Windows)

1. Baixe e extraia o pacote **`Okada Pedidos - Versao Beta.zip`**.
2. Dê dois cliques no arquivo:
   👉 **`Instalar Okada Pedidos.bat`**
3. Confirme a instalação permanente em `C:\Users\<SeuUsuario>\Okada Pedidos`.
4. O instalador removerá versões/atalhos antigos automaticamente e criará o atalho oficial **Okada Pedidos** na sua Área de Trabalho.

---

## 🔄 Como Funciona a Atualização Automática

- **Dispositivos instalados:** Sempre que o aplicativo é iniciado pelo atalho da Área de Trabalho com conexão à internet, o servidor local (`servidor.ps1`) verifica este repositório, baixa automaticamente novas tabelas de preços, cadastros e melhorias de sistema em segundo plano e abre o aplicativo já atualizado.
- **Segurança:** Os dados cadastrais sensíveis permanecem criptografados (`dados.enc`) e o acesso ao aplicativo é protegido por credencial local.

---

© **Okada Representações** — Uso exclusivo interno e representantes autorizados.
