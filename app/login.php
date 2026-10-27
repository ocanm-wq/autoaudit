<?php
/**
 * AutoAudit - Inicio de sesión
 *
 * El usuario y la contraseña son los de PostgreSQL. Entrar equivale a
 * lograr conectarse a la base de datos: la aplicación no tiene su propia
 * tabla de usuarios.
 */

require_once __DIR__ . '/lib/layout.php';

aa_sesion_iniciar();

if (aa_hay_sesion()) {
    header('Location: index.php');
    exit;
}

$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!aa_token_valido($_POST['token'] ?? null)) {
        $error = 'La sesión expiró. Intente de nuevo.';
    } else {
        $usuario  = is_string($_POST['usuario'] ?? null) ? trim($_POST['usuario']) : '';
        $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';

        if ($usuario === '') {
            $error = 'Escriba su usuario de PostgreSQL.';
        } else {
            $error = aa_login($usuario, $password);
            if ($error === null) {
                header('Location: index.php');
                exit;
            }
        }
    }
}

aa_encabezado_simple('Iniciar sesión');
?>
<div class="container-xxl aa-login">
    <div class="authentication-wrapper authentication-basic container-p-y">
        <div class="authentication-inner">
            <div class="card">
                <div class="card-body">

                    <div class="app-brand justify-content-center aa-brand">
                        <span class="app-brand-link gap-2">
                            <span class="app-brand-logo"><?= aa_logo_svg() ?></span>
                            <span class="aa-brand-textos">
                                <span class="aa-brand-text">Auto<span>Audit</span></span>
                                <span class="aa-brand-sub">Auditoría de datos</span>
                            </span>
                        </span>
                    </div>

                    <h4 class="mb-2">Iniciar sesión</h4>
                    <p class="mb-4 text-muted">
                        Use su usuario de PostgreSQL. Sus permisos dependen del rol
                        que tenga asignado en la base de datos.
                    </p>

                    <?php if ($error !== null): ?>
                        <?php aa_aviso('error', $error); ?>
                    <?php endif; ?>

                    <form method="post" class="mb-2" autocomplete="off">
                        <input type="hidden" name="token" value="<?= aa_esc(aa_token()) ?>">

                        <div class="mb-3">
                            <label for="usuario" class="form-label">Usuario</label>
                            <div class="input-group input-group-merge">
                                <span class="input-group-text"><i class="bx bx-user"></i></span>
                                <input type="text" class="form-control" id="usuario" name="usuario"
                                       placeholder="usuario de PostgreSQL" required autofocus
                                       value="<?= aa_esc(is_string($_POST['usuario'] ?? null) ? $_POST['usuario'] : '') ?>">
                            </div>
                        </div>

                        <div class="mb-4 form-password-toggle">
                            <label class="form-label" for="password">Contraseña</label>
                            <div class="input-group input-group-merge">
                                <span class="input-group-text"><i class="bx bx-lock-alt"></i></span>
                                <input type="password" id="password" class="form-control" name="password"
                                       placeholder="••••••••">
                                <span class="input-group-text cursor-pointer"><i class="bx bx-hide"></i></span>
                            </div>
                        </div>

                        <button class="btn btn-primary d-grid w-100" type="submit">Entrar</button>
                    </form>

                </div>
            </div>
        </div>
    </div>
</div>
<?php
aa_pie_simple();
