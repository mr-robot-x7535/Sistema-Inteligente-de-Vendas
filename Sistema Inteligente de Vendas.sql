CREATE DATABASE megabrain_analytics
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE megabrain_analytics;

CREATE TABLE clientes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(190) NOT NULL UNIQUE,
    telefone VARCHAR(25),
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE produtos (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    categoria VARCHAR(100) NOT NULL,
    preco DECIMAL(12,2) NOT NULL,
    estoque INT UNSIGNED NOT NULL DEFAULT 0,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_produto_preco CHECK (preco >= 0)
);

CREATE TABLE pedidos (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cliente_id BIGINT UNSIGNED NOT NULL,
    status ENUM(
        'PENDENTE',
        'PAGO',
        'ENVIADO',
        'CANCELADO'
    ) NOT NULL DEFAULT 'PENDENTE',
    total DECIMAL(14,2) NOT NULL DEFAULT 0,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pedido_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES clientes(id),
    INDEX idx_pedidos_cliente_data (cliente_id, criado_em),
    INDEX idx_pedidos_status_data (status, criado_em)
);

CREATE TABLE itens_pedido (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    pedido_id BIGINT UNSIGNED NOT NULL,
    produto_id BIGINT UNSIGNED NOT NULL,
    quantidade INT UNSIGNED NOT NULL,
    preco_unitario DECIMAL(12,2) NOT NULL,
    subtotal DECIMAL(14,2)
        GENERATED ALWAYS AS (quantidade * preco_unitario) STORED,
    CONSTRAINT fk_item_pedido
        FOREIGN KEY (pedido_id)
        REFERENCES pedidos(id),
    CONSTRAINT fk_item_produto
        FOREIGN KEY (produto_id)
        REFERENCES produtos(id),
    CONSTRAINT chk_item_quantidade CHECK (quantidade > 0),
    CONSTRAINT chk_item_preco CHECK (preco_unitario >= 0),
    UNIQUE KEY uk_pedido_produto (pedido_id, produto_id)
);

CREATE TABLE movimentacoes_estoque (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    produto_id BIGINT UNSIGNED NOT NULL,
    pedido_id BIGINT UNSIGNED,
    tipo ENUM('ENTRADA', 'SAIDA', 'ESTORNO') NOT NULL,
    quantidade INT UNSIGNED NOT NULL,
    descricao VARCHAR(255),
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_mov_produto
        FOREIGN KEY (produto_id)
        REFERENCES produtos(id),
    CONSTRAINT fk_mov_pedido
        FOREIGN KEY (pedido_id)
        REFERENCES pedidos(id),
    CONSTRAINT chk_mov_quantidade CHECK (quantidade > 0),
    INDEX idx_mov_produto_data (produto_id, criado_em)
);


USE megabrain_analytics;

INSERT INTO clientes (nome, email, telefone) VALUES
('Ana Silva', 'ana@example.com', '11999990001'),
('Bruno Costa', 'bruno@example.com', '11999990002'),
('Carla Souza', 'carla@example.com', '11999990003');

INSERT INTO produtos (nome, categoria, preco, estoque) VALUES
('Notebook Pro', 'Informática', 4500.00, 20),
('Mouse Gamer', 'Periféricos', 180.00, 100),
('Teclado Mecânico', 'Periféricos', 320.00, 50),
('Monitor 27', 'Monitores', 1250.00, 15);

INSERT INTO pedidos (cliente_id, status) VALUES
(1, 'PAGO'),
(2, 'PENDENTE'),
(3, 'PAGO');

INSERT INTO itens_pedido
    (pedido_id, produto_id, quantidade, preco_unitario)
VALUES
    (1, 1, 1, 4500.00),
    (1, 2, 2, 180.00),
    (2, 3, 1, 320.00),
    (3, 4, 2, 1250.00);

UPDATE pedidos p
SET total = (
    SELECT COALESCE(SUM(i.subtotal), 0)
    FROM itens_pedido i
    WHERE i.pedido_id = p.id
);


DELIMITER $$

CREATE TRIGGER trg_item_pedido_insert
BEFORE INSERT ON itens_pedido
FOR EACH ROW
BEGIN
    DECLARE estoque_atual INT UNSIGNED;
    DECLARE produto_ativo BOOLEAN;

    SELECT estoque, ativo
    INTO estoque_atual, produto_ativo
    FROM produtos
    WHERE id = NEW.produto_id
    FOR UPDATE;

    IF produto_ativo = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Produto inativo';
    END IF;

    IF estoque_atual < NEW.quantidade THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Estoque insuficiente';
    END IF;
END$$

CREATE TRIGGER trg_item_pedido_insert_after
AFTER INSERT ON itens_pedido
FOR EACH ROW
BEGIN
    UPDATE produtos
    SET estoque = estoque - NEW.quantidade
    WHERE id = NEW.produto_id;

    INSERT INTO movimentacoes_estoque
        (produto_id, pedido_id, tipo, quantidade, descricao)
    VALUES
        (NEW.produto_id, NEW.pedido_id, 'SAIDA',
         NEW.quantidade, 'Venda registrada');

    UPDATE pedidos
    SET total = (
        SELECT COALESCE(SUM(subtotal), 0)
        FROM itens_pedido
        WHERE pedido_id = NEW.pedido_id
    )
    WHERE id = NEW.pedido_id;
END$$

DELIMITER ;


SELECT
    p.nome,
    SUM(i.quantidade) AS unidades_vendidas,
    SUM(i.subtotal) AS faturamento
FROM itens_pedido i
JOIN produtos p ON p.id = i.produto_id
JOIN pedidos pe ON pe.id = i.pedido_id
WHERE pe.status IN ('PAGO', 'ENVIADO')
GROUP BY p.id, p.nome
ORDER BY unidades_vendidas DESC, faturamento DESC;


SELECT
    c.nome,
    c.email,
    COUNT(p.id) AS total_pedidos,
    SUM(p.total) AS valor_comprado
FROM clientes c
JOIN pedidos p ON p.cliente_id = c.id
WHERE p.status IN ('PAGO', 'ENVIADO')
GROUP BY c.id, c.nome, c.email
ORDER BY valor_comprado DESC;


SELECT
    id,
    nome,
    estoque,
    CASE
        WHEN estoque = 0 THEN 'SEM ESTOQUE'
        WHEN estoque <= 5 THEN 'ESTOQUE CRITICO'
        WHEN estoque <= 10 THEN 'REPOR EM BREVE'
        ELSE 'NORMAL'
    END AS situacao
FROM produtos
WHERE estoque <= 10
ORDER BY estoque ASC;


SELECT
    DATE_FORMAT(criado_em, '%Y-%m') AS mes,
    COUNT(*) AS pedidos,
    SUM(total) AS faturamento
FROM pedidos
WHERE status IN ('PAGO', 'ENVIADO')
GROUP BY DATE_FORMAT(criado_em, '%Y-%m')
ORDER BY mes DESC;


DELIMITER $$

CREATE PROCEDURE sp_resumo_vendas(
    IN data_inicio DATE,
    IN data_fim DATE
)
BEGIN
    IF data_inicio IS NULL
       OR data_fim IS NULL
       OR data_inicio > data_fim THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Periodo de datas invalido';
    END IF;

    SELECT
        COUNT(*) AS quantidade_pedidos,
        COALESCE(SUM(total), 0) AS faturamento_total,
        COALESCE(AVG(total), 0) AS ticket_medio
    FROM pedidos
    WHERE status IN ('PAGO', 'ENVIADO')
      AND criado_em >= data_inicio
      AND criado_em < DATE_ADD(data_fim, INTERVAL 1 DAY);
END$$

DELIMITER ;

CALL sp_resumo_vendas('2026-01-01', '2026-12-31');