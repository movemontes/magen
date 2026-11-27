"""Monta o Magen para Windows: uma pasta com o Magen.exe e, se houver Inno Setup, o instalador.

Rode no Windows, dentro da pasta windows\\ do projeto, com o Python do .venv:

    .venv\\Scripts\\python build_win.py

Sai em:
- dist\\Magen\\Magen.exe                (o app, o serviço e os comandos de administrador num só)
- dist\\Magen-<versão>-win-setup.exe    (instalador; precisa do Inno Setup 6: https://jrsoftware.org/isinfo.php)
- dist\\Magen-<versão>-win.zip          (se não houver Inno Setup; aí o serviço não se instala sozinho)

Diferente do Treco, o instalador do Magen PEDE administrador: um bloqueador precisa mexer no DNS
do Windows e rodar como serviço. Ele instala em Arquivos de Programas, liga o serviço "Magen" e
põe o ícone para abrir com o Windows (para todas as contas).

A atualização automática procura na release do GitHub um arquivo terminado em "-win-setup.exe".
Sem certificado de assinatura, o Windows mostra "O Windows protegeu o computador": a pessoa clica em
"Mais informações" > "Executar assim mesmo". Isso só é preciso na primeira vez.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from magen_win.version import VERSION  # noqa: E402

DIST = os.path.join(HERE, "dist")
WORK = os.path.join(HERE, "build")
APP_DIR = os.path.join(DIST, "Magen")
ISCC_PLACES = (r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe", r"C:\Program Files\Inno Setup 6\ISCC.exe")
CLASH = ("ClashGrotesk-Medium.otf", "ClashGrotesk-Semibold.otf")


def run(command, **kw):
    print("»", " ".join(os.path.basename(c) if i == 0 else c for i, c in enumerate(command))[:160])
    subprocess.run(command, check=True, **kw)


def make_ico(target):
    """Ícone do app (o mesmo broquel com M do Mac, de Resources/icone/icone-1024.png)."""
    from PIL import Image
    big = Image.open(os.path.join(REPO, "Resources", "icone", "icone-1024.png")).convert("RGBA")
    big.save(target, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    return target


def assets_folder():
    """Junta imagens e fontes numa pasta só, que vai para dentro do .exe como "assets"."""
    d = os.path.join(WORK, "assets")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(d, "fonts"))
    for name in ("escudo-512.png", "icone-1024.png"):
        shutil.copy(os.path.join(REPO, "Resources", "icone", name), d)
    for name in ("Archivo-Variable.ttf", "OFL.txt"):
        shutil.copy(os.path.join(REPO, "Resources", "fonts", name), os.path.join(d, "fonts"))
    # Clash Grotesk (licença ITF FFL): pode ir dentro do app, mas nunca no GitHub.
    private = os.path.join(HERE, "fontes-privadas")
    if all(os.path.isfile(os.path.join(private, n)) for n in CLASH):
        for n in CLASH:
            shutil.copy(os.path.join(private, n), os.path.join(d, "fonts"))
    else:
        print("Aviso: sem a Clash Grotesk em windows\\fontes-privadas\\ (o app usa a Segoe UI).")
    return d


def build_app():
    if sys.platform != "win32":
        raise SystemExit("Este roteiro é para rodar no Windows.")
    os.makedirs(WORK, exist_ok=True)
    icon = make_ico(os.path.join(tempfile.mkdtemp(), "Magen.ico"))
    sep = os.pathsep
    command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--windowed",
               "--name", "Magen", "--icon", icon,
               "--distpath", DIST, "--workpath", WORK, "--specpath", WORK,
               "--add-data", f"{assets_folder()}{sep}assets",
               "--add-data", f"{HERE}/magen_win/data{sep}magen_win/data",
               "--collect-submodules", "magen_win",
               "--hidden-import", "pystray._win32",
               "--hidden-import", "win32timezone",  # o pywin32 precisa dele para rodar como serviço
               "--hidden-import", "servicemanager", "--hidden-import", "win32serviceutil",
               "--collect-data", "certifi",
               "--exclude-module", "pytest", "--exclude-module", "IPython", "--exclude-module", "numpy",
               os.path.join(HERE, "magen.py")]
    run(command, cwd=HERE)
    shutil.copy(icon, os.path.join(APP_DIR, "Magen.ico"))


INNO = r'''
[Setup]
AppId={{9B3F6C2A-4E8D-4A1B-B6E2-5D7C1A9E3F40}
AppName=Magen
AppVersion=%(version)s
AppPublisher=Magen (grátis)
AppPublisherURL=https://movemontes.github.io/magen
DefaultDirName={autopf}\Magen
DefaultGroupName=Magen
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=%(dist)s
OutputBaseFilename=Magen-%(version)s-win-setup
SetupIconFile=%(icon)s
UninstallDisplayIcon={app}\Magen.exe
UninstallDisplayName=Magen
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
pt.StartingService=Ligando a proteção (o DNS do Windows passa pelo Magen)...
en.StartingService=Turning protection on (Windows DNS goes through Magen)...
pt.RemoveTitle=Remover o Magen?
en.RemoveTitle=Remove Magen?
pt.RemoveText=Sem o Magen, os sites adultos voltam a abrir neste computador. Se for um momento de tentação, feche esta janela e respire.%%n%%nPara remover, digite exatamente:%%n%%nquero remover a proteção
en.RemoveText=Without Magen, adult sites will open on this computer again. If this is a moment of temptation, close this window and breathe.%%n%%nTo remove it, type exactly:%%n%%ni want to remove the protection
pt.RemoveSentence=quero remover a proteção
en.RemoveSentence=i want to remove the protection
pt.RemoveWrong=A frase não confere. Nada foi removido.
en.RemoveWrong=The sentence doesn't match. Nothing was removed.

[Files]
Source: "%(app)s\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Magen"; Filename: "{app}\Magen.exe"

[Registry]
; O ícone perto do relógio abre com o Windows, em todas as contas (só o administrador tira).
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Magen"; ValueData: """{app}\Magen.exe"" --login"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Magen.exe"; Parameters: "--install-service"; StatusMsg: "{cm:StartingService}"; Flags: runhidden waituntilterminated
; Reabre o app na conta da pessoa (também depois de uma atualização silenciosa).
Filename: "{app}\Magen.exe"; Description: "{cm:LaunchProgram,Magen}"; Flags: nowait postinstall runasoriginaluser

[UninstallRun]
Filename: "{app}\Magen.exe"; Parameters: "--uninstall-service"; Flags: runhidden waituntilterminated; RunOnceId: "MagenService"

[Code]
// Antes de trocar os arquivos: para o serviço (ele devolve o DNS do Windows ao parar).
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\Magen.exe')) then
    Exec(ExpandConstant('{app}\Magen.exe'), '--stop-service', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

// Remover é difícil de propósito: pede a mesma frase do app.
// O app já pede a frase e chama o desinstalador com /MAGENOK.
function InitializeUninstall(): Boolean;
var
  Form: TSetupForm;
  Info: TNewStaticText;
  Edit: TNewEdit;
  OK, Cancel: TNewButton;
begin
  Result := True;
  if UninstallSilent or (Pos('/MAGENOK', Uppercase(GetCmdTail)) > 0) then
    Exit;
  Form := CreateCustomForm(ScaleX(440), ScaleY(260), False, True);
  try
    Form.Caption := CustomMessage('RemoveTitle');
    Info := TNewStaticText.Create(Form);
    Info.Parent := Form;
    Info.Left := ScaleX(16); Info.Top := ScaleY(14);
    Info.Width := Form.ClientWidth - ScaleX(32); Info.Height := ScaleY(140);
    Info.AutoSize := False; Info.WordWrap := True;
    Info.Caption := CustomMessage('RemoveText');
    Edit := TNewEdit.Create(Form);
    Edit.Parent := Form;
    Edit.Left := ScaleX(16); Edit.Top := ScaleY(166); Edit.Width := Form.ClientWidth - ScaleX(32);
    OK := TNewButton.Create(Form);
    OK.Parent := Form; OK.Caption := 'OK'; OK.ModalResult := mrOk; OK.Default := True;
    OK.Left := Form.ClientWidth - ScaleX(196); OK.Top := ScaleY(210); OK.Width := ScaleX(85);
    Cancel := TNewButton.Create(Form);
    Cancel.Parent := Form; Cancel.Caption := SetupMessage(msgButtonCancel); Cancel.ModalResult := mrCancel;
    Cancel.Cancel := True;
    Cancel.Left := Form.ClientWidth - ScaleX(101); Cancel.Top := ScaleY(210); Cancel.Width := ScaleX(85);
    Form.ActiveControl := Edit;
    if Form.ShowModal() <> mrOk then
      Result := False
    else if Lowercase(Trim(Edit.Text)) <> CustomMessage('RemoveSentence') then
    begin
      MsgBox(CustomMessage('RemoveWrong'), mbInformation, MB_OK);
      Result := False;
    end;
  finally
    Form.Free();
  end;
end;
'''


def build_installer():
    iscc = next((p for p in ISCC_PLACES if os.path.isfile(p)), shutil.which("ISCC"))
    if not iscc:
        archive = shutil.make_archive(os.path.join(DIST, f"Magen-{VERSION}-win"), "zip", DIST, "Magen")
        print("Sem Inno Setup: fiz só o .zip (sem instalador, o serviço não se instala sozinho).")
        return archive
    script = os.path.join(WORK, "Magen.iss")
    with open(script, "w", encoding="utf-8-sig") as f:
        f.write(INNO % {"version": VERSION, "dist": DIST, "app": APP_DIR,
                        "icon": os.path.join(APP_DIR, "Magen.ico")})
    run([iscc, "/Q", script])
    return os.path.join(DIST, f"Magen-{VERSION}-win-setup.exe")


if __name__ == "__main__":
    build_app()
    out = build_installer()
    print("Pronto:", os.path.join(APP_DIR, "Magen.exe"))
    print("Para passar adiante:", out, f"({os.path.getsize(out) / 1e6:.0f} MB)")
