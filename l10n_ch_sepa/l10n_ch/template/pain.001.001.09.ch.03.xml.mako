<?xml version='1.0' encoding='UTF-8'?>
<%!
def bic(bank_acc):
    """Plain function (no mako def), so it can be used in conditions."""
    code = bank_acc.bank.bic or bank_acc.bank_bic or ''
    return code.replace(' ', '').upper()
%><%doc>\
  Swiss Payment Standards (SPS) 2022+: pain.001.001.09.ch.03
  Standalone template (does not inherit the pain.001.001.03 base template,
  as the structure of version 09 differs: ReqdExctnDt/Dt, BICFI,
  InitgPty without postal address, CtctDtls/Othr with ChanlTp).
</%doc>\
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.09" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:iso:std:iso:20022:tech:xsd:pain.001.001.09 pain.001.001.09.ch.03.xsd">
  <CstmrCdtTrfInitn>
    <GrpHdr>
      <MsgId>${order.reference}</MsgId>
      <CreDtTm>${thetime.strftime("%Y-%m-%dT%H:%M:%S")}</CreDtTm>
      <NbOfTxs>${len(order.line_ids)}</NbOfTxs>
      <%
      control_sum = sum([line.amount_currency for line in order.line_ids])
      company = order.user_id.company_id
      %>\
      <CtrlSum>${control_sum}</CtrlSum>
      <InitgPty>
        <Nm>${company.name}</Nm>
        <CtctDtls>
          <Othr>
            <ChanlTp>NAME</ChanlTp>
            <Id>Odoo l10n_ch_sepa</Id>
          </Othr>
          % if module_version:
          <Othr>
            <ChanlTp>VRSN</ChanlTp>
            <Id>${module_version}</Id>
          </Othr>
          % endif
        </CtctDtls>
      </InitgPty>
    </GrpHdr>
% for line in order.line_ids:
    <%
    today = thetime.strftime("%Y-%m-%d")
    invoice = line.move_line_id.invoice
    %>\
    <PmtInf>
      <PmtInfId>${line.name}</PmtInfId>
      <PmtMtd>TRF</PmtMtd>
      <BtchBookg>false</BtchBookg>
      <ReqdExctnDt>
        <Dt>${line.date if line.date and line.date > today else today}</Dt>
      </ReqdExctnDt>
      <Dbtr>
        <Nm>${company.name}</Nm>\
        ${address(company.partner_id)}\
      </Dbtr>
      <DbtrAcct>\
        ${acc_id(order.mode.bank_id)}\
      </DbtrAcct>
      <DbtrAgt>
        <FinInstnId>
          <BICFI>${bic(order.mode.bank_id)}</BICFI>
        </FinInstnId>
      </DbtrAgt>
      <CdtTrfTxInf>
        <PmtId>
          <InstrId>${line.name}</InstrId>
          <EndToEndId>${line.name}</EndToEndId>
        </PmtId>
        <Amt>
          <InstdAmt Ccy="${line.currency.name}">${line.amount_currency}</InstdAmt>
        </Amt>
        <ChrgBr>SLEV</ChrgBr>
        % if bic(line.bank_id):
        <CdtrAgt>
          <FinInstnId>
            <BICFI>${bic(line.bank_id)}</BICFI>
          </FinInstnId>
        </CdtrAgt>
        % endif
        <Cdtr>
          <Nm>${line.partner_id.name}</Nm>\
          ${address(line.partner_id)}\
        </Cdtr>
        <CdtrAcct>\
          ${acc_id(line.bank_id)}\
        </CdtrAcct>\
        ${rmt_inf(line, invoice)}\
      </CdtTrfTxInf>
    </PmtInf>
% endfor
  </CstmrCdtTrfInitn>
</Document>
<%def name="rmt_inf(line, invoice)">
<%doc>\
  Remittance information depending on the invoice reference type.
  Only one Ustrd or one Strd is allowed in the CH version.
  ISR/ESR (bvr) has been discontinued with SPS 2022: the reference is
  passed as unstructured information.
</%doc>\
  % if invoice:
    % if invoice.reference_type == 'QRR':
        <RmtInf>
          <Strd>
            <CdtrRefInf>
              <Tp>
                <CdOrPrtry>
                  <Prtry>QRR</Prtry>
                </CdOrPrtry>
              </Tp>
              <Ref>${invoice.reference.replace(' ', '')}</Ref>
            </CdtrRefInf>
            % if invoice.supplier_invoice_number:
            <AddtlRmtInf>${invoice.supplier_invoice_number[:140]}</AddtlRmtInf>
            % endif
          </Strd>
        </RmtInf>
    % elif invoice.reference_type == 'SCOR':
        <RmtInf>
          <Strd>
            <CdtrRefInf>
              <Tp>
                <CdOrPrtry>
                  <Cd>SCOR</Cd>
                </CdOrPrtry>
              </Tp>
              <Ref>${line.communication.replace(' ', '')}</Ref>
            </CdtrRefInf>
            % if invoice.supplier_invoice_number:
            <AddtlRmtInf>${invoice.supplier_invoice_number[:140]}</AddtlRmtInf>
            % endif
          </Strd>
        </RmtInf>
    % elif invoice.reference_type == 'bvr' and invoice.reference:
        <RmtInf>
          <Ustrd>${invoice.reference.replace(' ', '')[:140]}</Ustrd>
        </RmtInf>
    % elif invoice.reference_type == 'none' and invoice.supplier_invoice_number:
        <RmtInf>
          <Ustrd>${invoice.supplier_invoice_number[:140]}</Ustrd>
        </RmtInf>
    % endif
  % endif
</%def>
<%def name="address(partner)">
          <PstlAdr>
            % if partner.street:
            <StrtNm>${partner.street[:70]}</StrtNm>
            % endif
            % if partner.zip:
            <PstCd>${partner.zip[:16]}</PstCd>
            % endif
            % if partner.city:
            <TwnNm>${partner.city[:35]}</TwnNm>
            % endif
            <Ctry>${partner.country_id.code or partner.company_id.country_id.code}</Ctry>
          </PstlAdr>
</%def>
<%def name="acc_id(bank_acc)">
          <Id>
            % if bank_acc.state == 'iban':
            <IBAN>${bank_acc.acc_number.replace(' ', '')}</IBAN>
            % else:
            <Othr>
              <Id>${bank_acc.get_account_number()}</Id>
            </Othr>
            % endif
          </Id>
</%def>
